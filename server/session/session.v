module session

import server.internal.network
import server.internal.auth
import protocol
import protocol.enums
import protocol.types
import server.internal.logger
import server.conf
import server.world
import server.player.playerdb
import server.permission
import server.cmd
import sync

pub const players_dir = 'players'
pub const player_eye_height = f32(1.62)

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
	transport        &network.Session = unsafe { nil }
	hub              &Hub             = unsafe { nil }
	state            State            = .handshake
	cfg              conf.Config
	generator        world.Generator = world.VoidGenerator{}
	identity         auth.Identity
	runtime_id       u64
	pos_mutex        &sync.Mutex = sync.new_mutex()
	position         types.Vector3
	pitch            f32
	yaw              f32
	head_yaw         f32
	spawned          bool
	inv_opened       bool
	game_mode        int
	health           f32 = 20.0
	prev_y           f32
	vy               f32
	dead             bool
	held_item        types.ItemStackWrapper
	inv_stacks       map[int]types.ItemStack
	inv_next_id      int = 1
	pending_creative ?types.ItemStack
	loaded_items     []playerdb.InvItem
	pending_radius   int
	perm             permission.Permissible
pub mut:
	log &logger.Logger = unsafe { nil }
}

pub fn (s &NetworkSession) has_permission(name string) bool {
	return s.perm.has_permission(name)
}

pub fn (s &NetworkSession) name() string {
	return s.identity.display_name
}

pub fn (mut s NetworkSession) find_player(name string) ?cmd.Sender {
	target := s.hub.session_by_name(name) or { return none }
	return target
}

pub fn new(mut transport network.Session, mut hub Hub, cfg conf.Config, log &logger.Logger) &NetworkSession {
	generator := world.new_generator(cfg.generator)
	return &NetworkSession{
		transport:  transport
		hub:        hub
		cfg:        cfg
		generator:  generator
		runtime_id: hub.allocate_runtime_id()
		position:   types.Vector3{0.0, f32(generator.spawn_y()) + player_eye_height, 0.0}
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
				s.log.warn('Failed to handle ${p.name()}: ${err}')
				s.disconnect('Internal server error')
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
	s.hub.handler.handle_quit(mut s)
	s.save_player_data()
	s.spawned = false
	s.hub.remove(s.runtime_id)
	s.hub.broadcast(s.player_list_remove_packet())
	s.hub.broadcast(s.remove_actor_packet())
	s.hub.broadcast(&protocol.TextPacket{
		@type:             int(enums.TextType.translation)
		needs_translation: true
		message:           '§e%multiplayer.player.left'
		parameters:        [s.identity.display_name]
	})
	s.log.info('${s.identity.display_name} left the game (${s.hub.count()} online)')
}

fn (mut s NetworkSession) update_movement(position types.Vector3, pitch f32, yaw f32, head_yaw f32) {
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
			} else if p is protocol.RequestChunkRadiusPacket {
				s.pending_radius = p.radius
			} else {
				s.log.debug('Dropped ${p.name()} (0x${p.pid().hex()}) in state login')
			}
		}
		.resource_packs {
			if p is protocol.ResourcePackClientResponsePacket {
				s.handle_resource_pack_response(p)!
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
