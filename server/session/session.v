module session

import server.internal.network
import protocol
import protocol.types
import server.internal.logger
import server.conf
import server.world
import server.world.db
import server.player
import server.cmd
import server.event
import server.form
import sync

pub const players_dir = 'players'
pub const player_eye_height = f32(1.62)
pub const player_half_width = f32(0.3)
pub const player_height = f32(1.8)

pub enum State {
	handshake
	login
	resource_packs
	play
	closed
}

// BreakProgress tracks the one block a player is currently breaking, armed by
// handle_start_break and checked in break_block to reject a destroy action
// that arrives before enough ticks have elapsed for the block's hardness.
struct BreakProgress {
	x            int
	y            int
	z            int
	block_id     int
	started_tick i64
}

@[heap]
pub struct NetworkSession {
mut:
	// player holds the gamestate fields.
	player    &player.Player    = unsafe { nil }
	transport network.Transport = FakeTransport{}
	breaking  ?BreakProgress
	hub       &Hub  = unsafe { nil }
	state     State = .handshake
	cfg       conf.Config
	world     &db.World       = unsafe { nil }
	generator world.Generator = world.VoidGenerator{}
	// world_runtime is the mutation routing counterpart to world.
	world_runtime &WorldRuntime = unsafe { nil }
	// world_epoch increments whenever the session changes runtime. World tasks
	// capture it at submission and drop stale work after a world switch.
	world_epoch i64
	// world_mutex guards world/generator/world_runtime/world_epoch.
	world_mutex        &sync.Mutex = sync.new_mutex()
	encryption_enabled bool
	runtime_id         u64
	spawned            bool
	inv_opened         bool
	movement_mutex     &sync.Mutex = sync.new_mutex()
	pending_movement   ?MovementSnapshot
	movement_scheduled bool
	pending_radius     int
	give_next_slot     int
	next_form_id       int
	pending_forms      map[int]form.Form
	last_place_ms      i64
	view_radius        int
	last_chunk_x       int
	last_chunk_z       int
	chunk_cache        map[u64]world.Chunk
	sent_chunks        map[u64]bool
	chunk_cache_mutex  &sync.Mutex = sync.new_mutex()
	chunk_stream_mutex &sync.Mutex = sync.new_mutex()
	transfer_mutex     &sync.Mutex = sync.new_mutex()
	cooldown_until     map[string]i64
	// Per session outbound delivery state. Packet queuing and writer lifecycle
	// are managed in outbound.v.
	outbound      chan OutboundMessage = chan OutboundMessage{cap: outbound_queue_capacity}
	outbound_done chan bool            = chan bool{cap: 1}
	// outbound_abort wakes an idle writer with nothing queued, so
	// close_outbound_once can always make it exit, not just when it's
	// mid send. See outbound.v.
	outbound_abort chan bool = chan bool{cap: 1}
	// writer_exited fires once the writer loop actually returns. Tests use
	// this to know the writer thread is gone, since outbound_done only
	// proves close_outbound_once ran, not that the writer itself exited.
	writer_exited chan bool   = chan bool{cap: 1}
	close_mutex   &sync.Mutex = sync.new_mutex()
	close_started bool
	// outbound_closing is set the moment a graceful disconnect is
	// accepted. Different from close_started: closing means no new
	// packets are accepted, but the disconnect message still has to
	// drain; close_started means the transport is actually closed.
	outbound_closing bool
	// outbound_bootstrap is true while a real connection still owns transport
	// writes during bootstrap. activate_outbound clears it once and only before
	// closing begins; test sessions default to the active state.
	outbound_bootstrap bool
	writer_mutex       &sync.Mutex = sync.new_mutex()
	writer_started     bool
	// handler is a per session attachment point, set via
	// set_handler(h). It receives the same event.Handler calls as the global
	// Bus for event dispatch sites that explicitly check it.
	handler ?event.Handler
pub mut:
	log &logger.Logger = unsafe { nil }
}

// set_handler attaches a per session event.Handler. Only wired into a subset
// of dispatch sites so far (chat.v's ChatData) as the demonstrated pattern. Not every event type
// checks it yet.
pub fn (mut s NetworkSession) set_handler(h event.Handler) {
	s.handler = h
}

pub fn (s &NetworkSession) has_permission(name string) bool {
	return s.player.has_permission(name)
}

// world_and_generator returns a consistent snapshot of the active world and
// generator under world_mutex, so callers never observe a torn generator
// interface value mid-swap.
fn (s &NetworkSession) world_and_generator() (&db.World, world.Generator) {
	mut m := s.world_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return s.world, s.generator
}

// current_world returns the active world under world_mutex, so block writes
// never race the world swap on the Hub job thread.
fn (s &NetworkSession) current_world() &db.World {
	mut m := s.world_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return s.world
}

// WorldBinding is a consistent snapshot of a session's world, generator,
// runtime and epoch, preventing callers from observing fields from different
// world switch states.
struct WorldBinding {
	world         &db.World
	world_runtime &WorldRuntime
	generator     world.Generator
	epoch         i64
}

// set_world_binding bumps world_epoch only during change_world, between
// deregistration from the old world and registration with the new one.
// Direct test calls intentionally simulate a completed transfer.
fn (mut s NetworkSession) set_world_binding(wr &WorldRuntime, generator world.Generator) {
	s.world_mutex.lock()
	s.world_runtime = wr
	s.world = wr.world
	s.generator = generator
	s.world_epoch++
	s.world_mutex.unlock()
}

fn (s &NetworkSession) world_binding() WorldBinding {
	mut m := s.world_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return WorldBinding{s.world, s.world_runtime, s.generator, s.world_epoch}
}

// current_world_runtime returns the runtime for the session's current world,
// avoiding a second name based lookup through Hub.
fn (mut s NetworkSession) current_world_runtime() &WorldRuntime {
	return s.world_binding().world_runtime
}

pub fn (s &NetworkSession) name() string {
	return s.player.name()
}

pub fn (s &NetworkSession) is_player() bool {
	return true
}

fn (s &NetworkSession) player_data_dir() string {
	if s.cfg.players_dir != '' {
		return s.cfg.players_dir
	}
	return players_dir
}

pub fn (mut s NetworkSession) find_player(name string) ?cmd.Sender {
	target := s.hub.session_by_name(name) or { return none }
	return target
}

pub fn new(mut transport network.Transport, mut hub Hub, cfg conf.Config, log &logger.Logger) &NetworkSession {
	mut generator := world.new_generator(cfg.generator)
	spawn_runtime := hub.default_world_runtime() or { unsafe { nil } }
	spawn_world := if !isnil(spawn_runtime) {
		spawn_runtime.world
	} else {
		&db.World(unsafe { nil })
	}
	if !isnil(spawn_world) {
		generator = spawn_world.make_generator(hub.build_generator(spawn_world))
	}
	mut p := player.new_player()
	p.reset_position(types.Vector3{0.0, f32(generator.spawn_y()) + player_eye_height, 0.0})
	return &NetworkSession{
		player:             p
		transport:          transport
		hub:                hub
		cfg:                cfg
		world:              spawn_world
		world_runtime:      spawn_runtime
		generator:          generator
		runtime_id:         hub.allocate_runtime_id()
		chunk_cache:        map[u64]world.Chunk{}
		sent_chunks:        map[u64]bool{}
		chunk_cache_mutex:  sync.new_mutex()
		chunk_stream_mutex: sync.new_mutex()
		log:                log
		outbound_bootstrap: true
	}
}

// A read error means the connection is already gone, so handle_loop aborts
// outbound delivery immediately instead of trying to drain it gracefully.
// Packet handling connection errors reach the same path on the next read.
pub fn (mut s NetworkSession) handle_loop() {
	for s.state != .closed {
		packets := s.transport.read() or {
			s.log.info('Connection ${s.transport.remote_addr()} ended: ${err}')
			s.abort_outbound()
			break
		}
		for p in packets {
			s.handle(p) or {
				if network.is_connection_closed(err) {
					s.log.info('Connection ${s.transport.remote_addr()} ended while handling ${p.name()}: ${err}')
				} else {
					s.log.warn('Failed to handle ${p.name()}: ${err}')
					s.reject_bootstrap('Internal server error')
				}
				break
			}
		}
	}
	s.leave()
	_ := <-s.outbound_done
}

// leave deregisters the session from its world before removing it from Hub,
// ensuring no WorldRuntime player entry outlives the session it references.
fn (mut s NetworkSession) leave() {
	if !s.spawned {
		s.hub.release_player_name(s.player.identity.display_name)
		return
	}
	s.save_player_data()
	// spawned is set false before transfer_mutex is acquired.
	s.spawned = false
	s.transfer_mutex.lock()
	mut wr := s.current_world_runtime()
	if !isnil(wr) {
		rid := s.runtime_id
		list_remove_pkt := s.player_list_remove_packet()
		remove_pkt := s.remove_actor_packet()
		world_call[bool](mut wr, fn [rid, list_remove_pkt, remove_pkt] (mut tx WorldTx) bool {
			tx.deregister_player(rid)
			tx.wr.broadcast_world(list_remove_pkt)
			tx.wr.broadcast_world(remove_pkt)
			return true
		}) or {}
	}
	s.transfer_mutex.unlock()
	s.hub.remove(s.runtime_id)
	s.hub.release_player_name(s.player.identity.display_name)
	mut ctx := event.new_context(event.QuitData{
		player:  s
		message: '§e${s.player.identity.display_name} left the game'
	})
	s.hub.events.player_quit(mut ctx)
	if !ctx.is_cancelled() && ctx.val.message != '' {
		s.hub.broadcast_message(ctx.val.message)
	}
	s.log.info('${s.player.identity.display_name} left the game (${s.hub.count()} online)')
}

fn (mut s NetworkSession) handle(p protocol.Packet) ! {
	match s.state {
		.handshake {
			if p is protocol.RequestNetworkSettingsPacket {
				s.handle_request_network_settings(p)!
			} else {
				s.log.debug('Dropped ${p.name()} (0x${p.pid().hex()}) in state handshake')
			}
		}
		.login {
			if p is protocol.LoginPacket {
				s.handle_login(p)!
			} else if p is protocol.ClientToServerHandshakePacket {
				s.handle_client_to_server_handshake(p)!
			} else if p is protocol.RequestChunkRadiusPacket {
				s.pending_radius = p.radius
			} else {
				s.log.debug('Dropped ${p.name()} (0x${p.pid().hex()}) in state login')
			}
		}
		.resource_packs {
			if p is protocol.ResourcePackClientResponsePacket {
				s.handle_resource_pack_response(p)!
			} else if p is protocol.ResourcePackChunkRequestPacket {
				s.handle_resource_pack_chunk_request(p)!
			} else if p is protocol.ClientToServerHandshakePacket {
				s.handle_client_to_server_handshake(p)!
			} else if p is protocol.RequestChunkRadiusPacket {
				s.pending_radius = p.radius
			} else {
				s.log.debug('Dropped ${p.name()} (0x${p.pid().hex()}) in state resource_packs')
			}
		}
		.play {
			if p is protocol.RequestChunkRadiusPacket {
				if should_stream_chunk_radius_async(s.state, s.spawned) {
					s.handle_play_chunk_radius_async(p)
				} else {
					s.handle_request_chunk_radius(p)!
				}
			} else if p is protocol.SubChunkRequestPacket {
				s.handle_sub_chunk_request(p)!
			} else if p is protocol.SetLocalPlayerAsInitializedPacket {
				s.handle_player_initialized(p)!
			} else if p is protocol.TextPacket {
				s.handle_text(p)!
			} else if p is protocol.MovePlayerPacket {
				s.update_movement(p.position, p.pitch, p.yaw, p.head_yaw)
			} else if p is protocol.PlayerAuthInputPacket {
				s.update_movement(p.position, p.pitch, p.yaw, p.head_yaw)
			} else if p is protocol.InteractPacket {
				s.handle_interact(p)!
			} else if p is protocol.ContainerClosePacket {
				s.handle_container_close(p)!
			} else if p is protocol.ItemStackRequestPacket {
				s.handle_item_stack_request(p)!
			} else if p is protocol.CommandRequestPacket {
				s.handle_command_request(p)!
			} else if p is protocol.InventoryTransactionPacket {
				s.handle_inventory_transaction(p)!
			} else if p is protocol.PlayerActionPacket {
				s.handle_player_action(p)!
			} else if p is protocol.BlockPickRequestPacket {
				s.handle_block_pick_request(p)!
			} else if p is protocol.MobEquipmentPacket {
				s.handle_mob_equipment(p)!
			} else if p is protocol.RespawnPacket {
				s.handle_respawn(p)!
			} else if p is protocol.ModalFormResponsePacket {
				s.handle_modal_form_response(p)!
			} else if p is protocol.BookEditPacket {
				s.handle_book_edit(p)!
			} else if p is protocol.BlockActorDataPacket {
				s.handle_block_actor_data(p)!
			}
		}
		else {}
	}
}

// disconnect queues a final DisconnectPacket after all pending packets and
// prevents anything else from being queued behind it. Repeated calls are
// harmless; a full queue falls back to an immediate abort.
pub fn (mut s NetworkSession) disconnect(message string) {
	s.mark_closed()
	result := s.try_enqueue(OutboundDisconnect{
		message: message
	}, true) or { panic('disconnect() called before activate_outbound(): ${err}') }
	if result == .queue_full {
		s.abort_outbound()
	}
}
