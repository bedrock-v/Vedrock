module session

import server.internal.network
import bedrock_v.protocol
import bedrock_v.protocol.types
import server.internal.logger
import server.conf
import server.world
import server.world.db
import server.player
import server.cmd
import server.entity
import server.event
import server.form
import sync
import bedrock_v.protocol.current as proto

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
// handle_start_break and advanced once per world tick by tick_breaking. It is
// checked in break_block to reject a destroy action that arrives before the
// block could actually have been mined.
struct BreakProgress {
	x            int
	y            int
	z            int
	block_id     int
	started_tick i64
mut:
	face      int
	speed     f32
	progress  f32
	fx_ticker int
}

// NetworkSession contains per connection transport and threading state. It remains a public type only where required
// across package boundaries; most of its methods stay private.
//
// External callers should interact with players through PlayerRef.
@[heap]
pub struct NetworkSession {
mut:
	// player holds the gamestate fields.
	player    &player.Player    = unsafe { nil }
	transport network.Transport = FakeTransport{}
	breaking  ?BreakProgress
	// breaking_mutex guards breaking, written by the session thread and
	// advanced by the owning world thread once per tick.
	breaking_mutex &sync.Mutex = sync.new_mutex()
	hub            &Hub        = unsafe { nil }
	state          State       = .handshake
	cfg            conf.Config
	world          &db.World       = unsafe { nil }
	generator      world.Generator = world.VoidGenerator{}
	// world_runtime is the mutation routing counterpart to world.
	world_runtime &WorldRuntime = unsafe { nil }
	// world_epoch increments whenever the session changes runtime. World tasks
	// capture it at submission and drop stale work after a world switch.
	world_epoch i64
	// world_mutex guards world/generator/world_runtime/world_epoch.
	world_mutex                 &sync.Mutex = sync.new_mutex()
	encryption_enabled          bool
	runtime_id                  u64
	spawned                     bool
	inv_opened                  bool
	open_container_pos          ?types.BlockPosition
	open_container_slot_net_ids map[int]int
	open_container_mutex        &sync.Mutex = sync.new_mutex()
	crafting_slot_net_ids   map[int]int
	crafting_workbench_open bool
	crafting_mutex          &sync.Mutex = sync.new_mutex()
	// cursor_net_id tracks whatever the client holds on its cursor
	// (FullContainerName.cursor_container)
	cursor_net_id      int
	cursor_mutex       &sync.Mutex = sync.new_mutex()
	movement_mutex     &sync.Mutex = sync.new_mutex()
	pending_movement   ?MovementSnapshot
	movement_scheduled bool
	// pending_teleport_ack is the position the server last told this client
	// to snap to (see expect_teleport_ack in movement.v). Client reported
	// movement is discarded until a report lands within
	// teleport_ack_tolerance of it.
	pending_teleport_ack ?types.Vector3
	pending_radius       int
	give_next_slot       int
	next_form_id         int
	pending_forms        map[int]form.Form
	forms_mutex          &sync.Mutex = sync.new_mutex()
	last_place_ms        i64
	view_radius          int
	last_chunk_x         int
	last_chunk_z         int
	sent_chunks          map[u64]bool
	// Set when a claimed column was released without reaching the client, so
	// the next movement re-sweeps even if the player never crosses into
	// another column. Guarded by chunk_stream_mutex.
	chunk_resend_pending bool
	chunk_stream_mutex   &sync.Mutex = sync.new_mutex()
	chunk_gen_mutex      &sync.Mutex = sync.new_mutex()
	transfer_mutex       &sync.Mutex = sync.new_mutex()
	cooldown_until       map[string]i64
	// Per session outbound delivery state. Packet queuing and writer lifecycle
	// are managed in outbound.v.
	// The queue carries ticket ids, not packets. A V channel keeps whatever was
	// written into a slot until that slot is written again, so sending payloads
	// through it left a session pinning its last outbound_queue_capacity
	// messages - megabytes of already-delivered chunk data - for as long as it
	// stayed connected. Tickets are a fixed 8 bytes; outbound_pending holds the
	// payload only until the writer takes it.
	outbound               chan u64 = chan u64{cap: outbound_queue_capacity}
	outbound_pending       map[u64]OutboundMessage
	outbound_pending_mutex &sync.Mutex = sync.new_mutex()
	outbound_next_ticket   u64
	outbound_done          chan bool = chan bool{cap: 1}
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
fn (mut s NetworkSession) set_handler(h event.Handler) {
	s.handler = h
}

fn (s &NetworkSession) has_permission(name string) bool {
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
// never race a concurrent world switch (see set_world_binding/change_world).
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

fn (s &NetworkSession) name() string {
	return s.player.name()
}

fn (s &NetworkSession) is_player() bool {
	return true
}

fn (s &NetworkSession) runtime_id() u64 {
	return s.runtime_id
}

fn (s &NetworkSession) is_dead() bool {
	return s.player.is_dead()
}

// self_ref returns a stable pointer to this session for closure captures.
// V closures capture struct receivers by value which would otherwise
// create a stale snapshot instead of preserving NetworkSession identity.
//
// NetworkSession is @[heap] and the returned pointer remains alive under
// this project's default Boehm GC. See self_ref_test.v for the cross thread
// lifetime regression test.
fn (mut s NetworkSession) self_ref() &NetworkSession {
	return unsafe { &s }
}

// dimensions satisfies entity.Actor. Returns the player's dimensions.
fn (s &NetworkSession) dimensions() entity.Dimensions {
	return entity.Dimensions{
		width:      player_half_width * 2
		height:     player_height
		eye_height: player_eye_height
	}
}

// feet_position returns the player's feet position. Player positions are
// stored at eye level, so this subtracts eye_height; entity positions
// already represent their feet.
fn (s &NetworkSession) feet_position() types.Vector3 {
	p := s.current_position()
	return types.Vector3{p.x, p.y - player_eye_height, p.z}
}

fn (mut s NetworkSession) find_player(name string) ?cmd.Sender {
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
		sent_chunks:        map[u64]bool{}
		chunk_stream_mutex: sync.new_mutex()
		chunk_gen_mutex:    sync.new_mutex()
		log:                log
		outbound_bootstrap: true
	}
}

// A read error or a is_connection_closed write error both mean the
// connection is already gone, so handle_loop aborts outbound delivery
// immediately instead of trying to drain it gracefully.
pub fn (mut s NetworkSession) handle_loop() {
	for s.state != .closed {
		packets := s.transport.read() or {
			s.log.info('Connection ${s.transport.remote_addr()} closed')
			s.log.debug('Connection ${s.transport.remote_addr()} ended: ${err}')
			s.abort_outbound()
			break
		}
		for p in packets {
			s.handle(p) or {
				if network.is_connection_closed(err) {
					s.log.info('Connection ${s.transport.remote_addr()} closed')
					s.log.debug('Connection ${s.transport.remote_addr()} ended while handling ${p.name()}: ${err}')
					s.abort_outbound()
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
	// spawned is set false before transfer_mutex is acquired.
	s.spawned = false
	s.transfer_mutex.lock()
	mut wr := s.current_world_runtime()
	if !isnil(wr) {
		rid := s.runtime_id
		list_remove_pkt := s.player_list_remove_packet()
		remove_pkt := s.remove_actor_packet()
		held_container := s.open_container_position()
		world_call[bool]('Session.leave', mut wr, fn [mut s, rid, list_remove_pkt, remove_pkt, held_container] (mut tx WorldTx) bool {
			// Must run before save_player_data below, so anything returned
			// to the inventory here is captured in the saved snapshot.
			s.release_crafting_state()
			tx.deregister_player(rid)
			if pos := held_container {
				tx.wr.world.release_container_hold(pos.x, pos.y, pos.z, rid)
			}
			tx.wr.broadcast_world(list_remove_pkt)
			tx.wr.broadcast_world(remove_pkt)
			return true
		}) or {}
	}
	s.transfer_mutex.unlock()
	s.save_player_data()
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
	s.log.info('${s.player.identity.display_name} left the game')
}

fn (mut s NetworkSession) handle(p protocol.Packet) ! {
	match s.state {
		.handshake {
			if p is proto.RequestNetworkSettingsPacket {
				s.handle_request_network_settings(p)!
			} else {
				s.log.debug('Dropped ${p.name()} (0x${p.pid().hex()}) in state handshake')
			}
		}
		.login {
			if p is proto.LoginPacket {
				s.handle_login(p)!
			} else if p is proto.ClientToServerHandshakePacket {
				s.handle_client_to_server_handshake(p)!
			} else if p is proto.RequestChunkRadiusPacket {
				s.pending_radius = p.chunk_radius
			} else {
				s.log.debug('Dropped ${p.name()} (0x${p.pid().hex()}) in state login')
			}
		}
		.resource_packs {
			if p is proto.ResourcePackClientResponsePacket {
				s.handle_resource_pack_response(p)!
			} else if p is proto.ResourcePackChunkRequestPacket {
				s.handle_resource_pack_chunk_request(p)!
			} else if p is proto.ClientToServerHandshakePacket {
				s.handle_client_to_server_handshake(p)!
			} else if p is proto.RequestChunkRadiusPacket {
				s.pending_radius = p.chunk_radius
			} else {
				s.log.debug('Dropped ${p.name()} (0x${p.pid().hex()}) in state resource_packs')
			}
		}
		.play {
			if p is proto.RequestChunkRadiusPacket {
				if should_stream_chunk_radius_async(s.state, s.spawned) {
					s.handle_play_chunk_radius_async(p)
				} else {
					s.handle_request_chunk_radius(p)!
				}
			} else if p is proto.SubChunkRequestPacket {
				s.handle_sub_chunk_request(p)!
			} else if p is proto.SetLocalPlayerAsInitializedPacket {
				s.handle_player_initialized(p)!
			} else if p is proto.TextPacket {
				s.handle_text(p)!
			} else if p is proto.MovePlayerPacket {
				s.update_movement(proto.vec3_from_array(p.position), p.rotation[0], p.rotation[1],
					p.y_head_rotation, p.on_ground)
			} else if p is proto.PlayerAuthInputPacket {
				s.handle_player_auth_input(p)!
			} else if p is proto.InteractPacket {
				s.handle_interact(p)!
			} else if p is proto.ContainerClosePacket {
				s.handle_container_close(p)!
			} else if p is proto.ItemStackRequestPacket {
				s.handle_item_stack_request(p)!
			} else if p is proto.CommandRequestPacket {
				s.handle_command_request(p)!
			} else if p is proto.InventoryTransactionPacket {
				s.handle_inventory_transaction(p)!
			} else if p is proto.PlayerActionPacket {
				s.handle_player_action(p)!
			} else if p is proto.BlockPickRequestPacket {
				s.handle_block_pick_request(p)!
			} else if p is proto.MobEquipmentPacket {
				s.handle_mob_equipment(p)!
			} else if p is proto.RespawnPacket {
				s.handle_respawn(p)!
			} else if p is proto.ModalFormResponsePacket {
				s.handle_modal_form_response(p)!
			} else if p is proto.BookEditPacket {
				s.handle_book_edit(p)!
			} else if p is proto.BlockActorDataPacket {
				s.handle_block_actor_data(p)!
			}
		}
		else {}
	}
}

// disconnect queues a final DisconnectPacket after all pending packets and
// prevents anything else from being queued behind it. Repeated calls are
// harmless; a full queue falls back to an immediate abort.
fn (mut s NetworkSession) disconnect(message string) {
	s.mark_closed()
	result := s.try_enqueue(OutboundDisconnect{
		message: message
	}, true) or { panic('disconnect() called before activate_outbound(): ${err}') }
	if result == .queue_full {
		s.abort_outbound()
	}
}
