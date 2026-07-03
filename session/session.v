module session

import math
import network
import auth
import protocol
import protocol.enums
import protocol.types
import nbt
import logger
import config
import world
import command
import storage

pub const resource_response_have_all_packs = 3
pub const resource_response_completed = 4

pub const interact_action_open_inventory = 6
pub const inventory_container_type = 0xff

pub const players_dir = 'players'

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
	cfg              config.Config
	generator        world.Generator = world.VoidGenerator{}
	identity         auth.Identity
	runtime_id       u64
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
	inv_stacks       map[int]types.ItemStack
	inv_next_id      int = 1
	pending_creative ?types.ItemStack
	loaded_items     []storage.InvItem
	pending_radius   int
pub mut:
	log &logger.Logger = unsafe { nil }
}

pub fn new(mut transport network.Session, mut hub Hub, cfg config.Config, log &logger.Logger) &NetworkSession {
	generator := world.new_generator(cfg.generator)
	return &NetworkSession{
		transport:  transport
		hub:        hub
		cfg:        cfg
		generator:  generator
		runtime_id: hub.allocate_runtime_id()
		position:   types.Vector3{0.0, f32(generator.spawn_y()), 0.0}
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
	s.vy = position.y - s.prev_y
	s.prev_y = position.y
	s.position = position
	s.pitch = pitch
	s.yaw = yaw
	s.head_yaw = head_yaw
	if s.spawned {
		s.hub.broadcast_except(s.runtime_id, s.move_player_packet())
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
			}
		}
		else {}
	}
}

fn (mut s NetworkSession) handle_request_network_settings(p protocol.RequestNetworkSettingsPacket) ! {
	s.log.debug('Client requested network settings (protocol ${p.protocol_version})')
	if p.protocol_version != protocol.current_protocol {
		status := if p.protocol_version < protocol.current_protocol {
			enums.PlayStatus.login_failed_client
		} else {
			enums.PlayStatus.login_failed_server
		}
		s.log.warn('Rejected client with protocol ${p.protocol_version} (server requires ${protocol.current_protocol})')
		s.transport.send(&protocol.PlayStatusPacket{
			status: int(status)
		})!
		s.disconnect('Incompatible client version. Server requires ${protocol.minecraft_version_network}.')
		return
	}
	settings := &protocol.NetworkSettingsPacket{
		compression_threshold:     s.cfg.compression_threshold
		compression_algorithm:     int(network.compression_flate)
		enable_client_throttling:  false
		client_throttle_threshold: 0
		client_throttle_scalar:    0.0
	}
	s.transport.send(settings)!
	s.transport.enable_compression(s.cfg.compression_threshold)
	s.state = .login
}

fn (mut s NetworkSession) handle_login(p protocol.LoginPacket) ! {
	identity := auth.parse_login_chain(p.auth_info_json, s.cfg.xbox_auth) or {
		s.log.warn('Authentication failed: ${err}')
		s.disconnect('Login failed: ${err}')
		return
	}
	s.identity = identity
	mode := if identity.xbox_authenticated { 'Xbox Live' } else { 'offline' }
	s.log.info('${identity.display_name} authenticated [${mode}] xuid=${identity.xuid} uuid=${identity.uuid}')
	s.transport.send(&protocol.PlayStatusPacket{
		status: int(enums.PlayStatus.login_success)
	})!
	s.start_resource_packs()!
}

fn (mut s NetworkSession) start_resource_packs() ! {
	s.transport.send(&protocol.ResourcePacksInfoPacket{
		must_accept: false
		entries:     []protocol.ResourcePackInfoEntry{}
	})!
	s.state = .resource_packs
}

fn (mut s NetworkSession) handle_resource_pack_response(p protocol.ResourcePackClientResponsePacket) ! {
	match p.status {
		resource_response_have_all_packs {
			s.transport.send(&protocol.ResourcePackStackPacket{
				must_accept:         false
				resource_pack_stack: []protocol.ResourcePackStackEntry{}
				base_game_version:   protocol.minecraft_version_network
				experiments:         types.Experiments{}
			})!
		}
		resource_response_completed {
			s.start_game()!
		}
		else {
			s.log.debug('Unhandled resource pack response status ${p.status}')
		}
	}
}

fn (mut s NetworkSession) player_key() string {
	if s.identity.xuid != '' {
		return s.identity.xuid
	}
	if s.identity.uuid != '' {
		return s.identity.uuid
	}
	return s.identity.display_name
}

fn (mut s NetworkSession) start_game() ! {
	s.game_mode = gamemode_id(s.cfg.gamemode)
	spawn_y := s.generator.spawn_y()
	s.position = types.Vector3{0.0, f32(spawn_y), 0.0}
	if data := storage.load_player(players_dir, s.player_key()) {
		s.position = types.Vector3{data.x, data.y, data.z}
		s.pitch = data.pitch
		s.yaw = data.yaw
		s.loaded_items = data.items
		s.game_mode = data.gamemode
	}
	s.transport.send(&protocol.StartGamePacket{
		entity_unique_id:               i64(s.runtime_id)
		entity_runtime_id:              s.runtime_id
		player_game_mode:               s.game_mode
		player_position:                s.position
		pitch:                          0.0
		yaw:                            0.0
		world_seed:                     0
		spawn_biome_type:               0
		dimension:                      0
		generator:                      1
		world_game_mode:                s.game_mode
		difficulty:                     1
		world_spawn:                    types.BlockPosition{0, spawn_y, 0}
		commands_enabled:               true
		multi_player_game:              true
		server_chunk_tick_radius:       s.cfg.view_distance
		player_permissions:             2
		base_game_version:              protocol.minecraft_version_network
		game_version:                   protocol.minecraft_version_network
		level_id:                       'Vedrock'
		world_name:                     s.cfg.motd
		multi_player_correlation_id:    '00000000-0000-0000-0000-000000000000'
		server_authoritative_inventory: true
		use_block_network_id_hashes:    s.generator.uses_blocks()
		property_data:                  nbt.RootTag{
			name: ''
			tag:  nbt.Tag(nbt.new_compound())
		}
		blocks:                         []protocol.BlockEntry{}
	})!
	s.transport.send(s.item_registry())!
	s.transport.send(s.creative_content())!
	s.transport.send(&protocol.BiomeDefinitionListPacket{
		biome_definitions: []protocol.BiomeDefinition{}
		string_list:       []string{}
	})!
	s.transport.send(&protocol.UpdateAbilitiesPacket{
		data: s.build_abilities()
	})!
	s.transport.send(adventure_settings())!
	s.transport.send(s.update_attributes())!
	s.transport.send(s.set_actor_data())!
	s.log.info('${s.identity.display_name} joined the game')
	s.state = .play
	if s.pending_radius > 0 {
		radius := s.pending_radius
		s.pending_radius = 0
		s.handle_request_chunk_radius(protocol.RequestChunkRadiusPacket{ radius: radius })!
	}
}

fn (mut s NetworkSession) handle_request_chunk_radius(p protocol.RequestChunkRadiusPacket) ! {
	mut radius := p.radius
	if radius > s.cfg.view_distance {
		radius = s.cfg.view_distance
	}
	if radius < 1 {
		radius = 1
	}
	s.transport.send(&protocol.ChunkRadiusUpdatedPacket{
		radius: radius
	})!
	s.transport.send(&protocol.NetworkChunkPublisherUpdatePacket{
		block_position: types.BlockPosition{int(s.position.x), int(s.position.y), int(s.position.z)}
		radius:         radius * 16
		saved_chunks:   []types.ChunkPosition{}
	})!
	s.send_spawn_chunks(radius)!
	s.transport.send(&protocol.PlayStatusPacket{
		status: int(enums.PlayStatus.player_spawn)
	})!
	s.log.debug('Sent ${(radius * 2 + 1) * (radius * 2 + 1)} chunks to ${s.identity.display_name}')
}

fn (mut s NetworkSession) send_spawn_chunks(radius int) ! {
	cx := int(math.floor(f64(s.position.x))) >> 4
	cz := int(math.floor(f64(s.position.z))) >> 4
	mut pending := 0
	for x in cx - radius .. cx + radius + 1 {
		for z in cz - radius .. cz + radius + 1 {
			mut chunk := s.generator.generate(x, z)
			for ov in s.hub.overrides_in_chunk(x, z) {
				chunk.set_block(ov.x & 15, ov.y, ov.z & 15, world.block_from_id(ov.id))
			}
			s.transport.queue(&protocol.LevelChunkPacket{
				chunk_position:  types.ChunkPosition{x, z}
				dimension_id:    0
				request_type:    protocol.level_chunk_request_explicit
				sub_chunk_count: u32(chunk.section_count())
				cache_enabled:   false
				extra_payload:   chunk.serialize().bytestr()
			})
			pending++
			if pending >= 4 {
				s.transport.flush()!
				pending = 0
			}
		}
	}
	s.transport.flush()!
}

fn (mut s NetworkSession) handle_interact(p protocol.InteractPacket) ! {
	if p.action != interact_action_open_inventory {
		return
	}
	if s.inv_opened {
		return
	}
	s.inv_opened = true
	s.transport.send(&protocol.ContainerOpenPacket{
		window_id:       0
		window_type:     inventory_container_type
		block_position:  types.BlockPosition{int(s.position.x), int(s.position.y), int(s.position.z)}
		actor_unique_id: i64(s.runtime_id)
	})!
}

fn (mut s NetworkSession) handle_container_close(p protocol.ContainerClosePacket) ! {
	s.inv_opened = false
	s.transport.send(&protocol.ContainerClosePacket{
		window_id:   p.window_id
		window_type: p.window_type
		server:      true
	})!
}

fn (mut s NetworkSession) handle_player_initialized(p protocol.SetLocalPlayerAsInitializedPacket) ! {
	if s.spawned {
		return
	}
	s.spawned = true
	for mut other in s.hub.snapshot() {
		s.deliver(other.player_list_add_packet())
		s.deliver(other.add_player_packet())
	}
	s.hub.add(s)
	s.hub.broadcast(s.player_list_add_packet())
	s.hub.broadcast_except(s.runtime_id, s.add_player_packet())
	s.hub.broadcast(&protocol.TextPacket{
		@type:             int(enums.TextType.translation)
		needs_translation: true
		message:           '§e%multiplayer.player.joined'
		parameters:        [s.identity.display_name]
	})
	s.transport.send(s.restore_inventory())!
	available := s.hub.commands.available_commands()
	s.transport.send(&available)!
	s.log.info('${s.identity.display_name} spawned in the world (${s.hub.count()} online)')
}

fn (mut s NetworkSession) handle_text(p protocol.TextPacket) ! {
	if p.@type != int(enums.TextType.chat) {
		return
	}
	message := p.message.trim_space()
	if message == '' {
		return
	}
	if message.starts_with('/') {
		s.run_command(message)!
		return
	}
	s.log.info('<${s.identity.display_name}> ${message}')
	s.hub.broadcast(&protocol.TextPacket{
		@type:       int(enums.TextType.chat)
		source_name: s.identity.display_name
		message:     message
	})
}

fn (mut s NetworkSession) handle_command_request(p protocol.CommandRequestPacket) ! {
	s.run_command(p.command)!
}

fn (mut s NetworkSession) run_command(line string) ! {
	s.log.info('${s.identity.display_name} issued command: ${line}')
	parts := line.trim_left('/').trim_space().split(' ')
	name := parts[0].to_lower()
	if name == 'gamemode' || name == 'gm' {
		s.run_gamemode(parts[1..])!
		return
	}
	ctx := command.Context{
		lang:           s.hub.lang
		sender_name:    s.identity.display_name
		player_count:   s.hub.count()
		max_players:    s.cfg.max_players
		server_motd:    s.cfg.motd
		uptime_seconds: s.hub.uptime_seconds()
		tps:            s.hub.tps
		load:           s.hub.load
	}
	output := s.hub.commands.dispatch(line, ctx)
	s.send_message(output)!
}

fn (mut s NetworkSession) send_message(message string) ! {
	s.transport.send(&protocol.TextPacket{
		@type:   int(enums.TextType.raw)
		message: message
	})!
}

fn gamemode_id(name string) int {
	return match name.to_lower() {
		'survival' { 0 }
		'adventure' { 2 }
		'spectator' { 6 }
		else { 1 }
	}
}

fn parse_gamemode(arg string) ?int {
	return match arg.to_lower() {
		'survival', 's', '0' { 0 }
		'creative', 'c', '1' { 1 }
		'adventure', 'a', '2' { 2 }
		'spectator', 'sp', '6' { 6 }
		else { none }
	}
}

fn gamemode_translation_key(mode int) string {
	return match mode {
		0 { 'gameMode.survival' }
		2 { 'gameMode.adventure' }
		6 { 'gameMode.spectator' }
		else { 'gameMode.creative' }
	}
}

fn (mut s NetworkSession) run_gamemode(args []string) ! {
	if args.len == 0 {
		s.send_translation('§c%commands.gamemode.usage', [])!
		return
	}
	mode := parse_gamemode(args[0]) or {
		s.send_translation('§c%commands.gamemode.usage', [])!
		return
	}
	s.set_gamemode(mode)
	s.send_translation('%commands.gamemode.success.self', ['%${gamemode_translation_key(mode)}'])!
}

fn (mut s NetworkSession) send_translation(message string, parameters []string) ! {
	s.transport.send(&protocol.TextPacket{
		@type:             int(enums.TextType.translation)
		needs_translation: true
		message:           message
		parameters:        parameters
	})!
}

fn (mut s NetworkSession) set_gamemode(mode int) {
	s.game_mode = mode
	s.transport.send(&protocol.SetPlayerGameTypePacket{
		gamemode: mode
	}) or {}
	s.transport.send(&protocol.UpdateAbilitiesPacket{
		data: s.build_abilities()
	}) or {}
}

pub fn (mut s NetworkSession) disconnect(message string) {
	s.transport.send(&protocol.DisconnectPacket{
		reason:           0
		message:          message
		filtered_message: ''
	}) or {}
	s.state = .closed
}
