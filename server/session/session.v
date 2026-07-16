module session

import server.internal.network
import server.internal.auth
import protocol
import protocol.types
import server.internal.logger
import server.conf
import server.world
import server.world.db
import server.player.playerdb
import server.permission
import server.cmd
import server.event
import server.form
import server.effect
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

@[heap]
pub struct NetworkSession {
mut:
	transport &network.Session = unsafe { nil }
	hub       &Hub             = unsafe { nil }
	state     State            = .handshake
	cfg       conf.Config
	world     &db.World       = unsafe { nil }
	generator world.Generator = world.VoidGenerator{}
	// world_mutex guards world and generator - both are swapped from the Hub
	// job thread on a world change while the session thread reads them.
	world_mutex        &sync.Mutex = sync.new_mutex()
	identity           auth.Identity
	encryption_enabled bool
	runtime_id         u64
	pos_mutex          &sync.Mutex = sync.new_mutex()
	position           types.Vector3
	pitch              f32
	yaw                f32
	head_yaw           f32
	spawned            bool
	inv_opened         bool
	game_mode          int
	health             f32 = 20.0
	prev_y             f32
	vy                 f32
	dead               bool
	held_item          types.ItemStackWrapper
	held_slot          int
	inv_stacks         map[int]types.ItemStack
	inv_slots          map[int]int
	inv_next_id        int = 1
	pending_creative   ?types.ItemStack
	loaded_items       []playerdb.InvItem
	pending_radius     int
	perm               permission.Permissible
	give_next_slot     int
	next_form_id       int
	pending_forms      map[int]form.Form
	last_place_ms      i64
	effects            effect.Manager
	has_last_death     bool
	last_death_pos     types.Vector3
pub mut:
	log &logger.Logger = unsafe { nil }
}

pub fn (s &NetworkSession) has_permission(name string) bool {
	return s.perm.has_permission(name)
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

pub fn (s &NetworkSession) name() string {
	return s.identity.display_name
}

pub fn (s &NetworkSession) is_player() bool {
	return true
}

pub fn (mut s NetworkSession) find_player(name string) ?cmd.Sender {
	target := s.hub.session_by_name(name) or { return none }
	return target
}

pub fn new(mut transport network.Session, mut hub Hub, cfg conf.Config, log &logger.Logger) &NetworkSession {
	mut generator := world.new_generator(cfg.generator)
	spawn_world := hub.default_world() or { &db.World(unsafe { nil }) }
	if !isnil(spawn_world) {
		generator = spawn_world.make_generator(hub.build_generator(spawn_world))
	}
	return &NetworkSession{
		transport:  transport
		hub:        hub
		cfg:        cfg
		world:      spawn_world
		generator:  generator
		runtime_id: hub.allocate_runtime_id()
		position:   types.Vector3{0.0, f32(generator.spawn_y()) + player_eye_height, 0.0}
		effects:    effect.new_manager()
		log:        log
	}
}

pub fn (mut s NetworkSession) deliver(p protocol.Packet) {
	s.transport.send(p) or {
		s.log.debug('Failed to deliver ${p.name()} to ${s.identity.display_name}: ${err}')
	}
}

pub fn (mut s NetworkSession) handle_loop() {
	for s.state != .closed {
		packets := s.transport.read() or {
			s.log.info('Connection ${s.transport.remote_addr()} ended: ${err}')
			break
		}
		for p in packets {
			s.handle(p) or {
				if network.is_connection_closed(err) {
					s.log.info('Connection ${s.transport.remote_addr()} ended while handling ${p.name()}: ${err}')
				} else {
					s.log.warn('Failed to handle ${p.name()}: ${err}')
					s.disconnect('Internal server error')
				}
				break
			}
		}
	}
	s.leave()
	s.transport.close()
}

fn (mut s NetworkSession) leave() {
	if !s.spawned {
		return
	}
	s.save_player_data()
	s.spawned = false
	s.hub.remove(s.runtime_id)
	s.hub.broadcast(s.player_list_remove_packet())
	s.hub.broadcast(s.remove_actor_packet())
	mut ctx := event.new_context(event.QuitData{
		player:  s
		message: '§e${s.identity.display_name} left the game'
	})
	s.hub.events.player_quit(mut ctx)
	if !ctx.is_cancelled() && ctx.val.message != '' {
		s.hub.broadcast_message(ctx.val.message)
	}
	s.log.info('${s.identity.display_name} left the game (${s.hub.count()} online)')
}

fn (mut s NetworkSession) update_movement(position types.Vector3, pitch f32, yaw f32, head_yaw f32) {
	// Diagnostic: log the client-reported position roughly every 2s (debug only)
	// so an idle drift can be traced to server vs client. If y climbs here while
	// the player stands still, the drift is coming from the client's authoritative
	// movement prediction, not from the server.
	if s.spawned && s.hub.current_tick % 40 == 0 {
		s.log.debug('move ${s.identity.display_name} pos=(${position.x:.2f}, ${position.y:.2f}, ${position.z:.2f})')
	}
	// Movement is high-frequency; only pay for the event when a listener exists.
	if s.spawned && s.hub.events.len() > 0 {
		mut ctx := event.new_context(event.MoveData{
			player: s
			x:      position.x
			y:      position.y
			z:      position.z
		})
		s.hub.events.player_move(mut ctx)
		if ctx.is_cancelled() {
			s.transport.send(&protocol.MovePlayerPacket{
				actor_runtime_id: s.runtime_id
				position:         s.position
				pitch:            s.pitch
				yaw:              s.yaw
				head_yaw:         s.head_yaw
				mode:             1
				on_ground:        false
			}) or {}
			return
		}
	}
	s.pos_mutex.lock()
	s.vy = position.y - s.prev_y
	s.prev_y = position.y
	s.position = position
	s.pos_mutex.unlock()
	s.pitch = pitch
	s.yaw = yaw
	s.head_yaw = head_yaw
	if s.spawned {
		s.hub.broadcast_except(s.runtime_id, s.move_actor_packet())
	}
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
				s.handle_request_chunk_radius(p)!
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
			}
		}
		else {}
	}
}

pub fn (mut s NetworkSession) disconnect(message string) {
	s.transport.send(&protocol.DisconnectPacket{
		reason:           0
		message:          message
		filtered_message: ''
	}) or {}
	s.state = .closed
}
