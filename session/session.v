module session

import network
import auth
import src as protocol
import src.enums
import src.types
import nbt
import logger
import config

pub const resource_response_have_all_packs = 3
pub const resource_response_completed = 4

pub const spawn_entity_runtime_id = u64(1)

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
	state     State            = .handshake
	cfg       config.Config
	identity  auth.Identity
pub mut:
	log &logger.Logger = unsafe { nil }
}

pub fn new(mut transport network.Session, cfg config.Config, log &logger.Logger) &NetworkSession {
	return &NetworkSession{
		transport: transport
		cfg:       cfg
		log:       log
	}
}

pub fn (mut s NetworkSession) handle_loop() {
	for s.state != .closed {
		packets := s.transport.read() or {
			s.log.debug('Connection ${s.transport.remote_addr()} ended: ${err}')
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
	s.transport.close()
}

fn (mut s NetworkSession) handle(p protocol.Packet) ! {
	match s.state {
		.handshake {
			if p is protocol.RequestNetworkSettingsPacket {
				s.handle_request_network_settings(p)!
			}
		}
		.login {
			if p is protocol.LoginPacket {
				s.handle_login(p)!
			}
		}
		.resource_packs {
			if p is protocol.ResourcePackClientResponsePacket {
				s.handle_resource_pack_response(p)!
			}
		}
		.play {
			if p is protocol.RequestChunkRadiusPacket {
				s.handle_request_chunk_radius(p)!
			} else if p is protocol.SetLocalPlayerAsInitializedPacket {
				s.handle_player_initialized(p)!
			}
		}
		else {}
	}
}

fn (mut s NetworkSession) handle_request_network_settings(p protocol.RequestNetworkSettingsPacket) ! {
	s.log.debug('Client requested network settings (protocol ${p.protocol_version})')
	settings := &protocol.NetworkSettingsPacket{
		compression_threshold:     s.cfg.compression_threshold
		compression_algorithm:     int(network.compression_zlib)
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

fn (mut s NetworkSession) start_game() ! {
	game_mode := gamemode_id(s.cfg.gamemode)
	s.transport.send(&protocol.StartGamePacket{
		entity_unique_id:            i64(spawn_entity_runtime_id)
		entity_runtime_id:           spawn_entity_runtime_id
		player_game_mode:            game_mode
		player_position:             types.Vector3{0.0, 64.0, 0.0}
		pitch:                       0.0
		yaw:                         0.0
		world_seed:                  0
		spawn_biome_type:            0
		dimension:                   0
		generator:                   1
		world_game_mode:             game_mode
		difficulty:                  1
		world_spawn:                 types.BlockPosition{0, 64, 0}
		commands_enabled:            true
		multi_player_game:           true
		server_chunk_tick_radius:    s.cfg.view_distance
		player_permissions:          2
		base_game_version:           protocol.minecraft_version_network
		game_version:                protocol.minecraft_version_network
		level_id:                    'Vedrock'
		world_name:                  s.cfg.motd
		multi_player_correlation_id: '00000000-0000-0000-0000-000000000000'
		server_authoritative_inventory: true
		property_data:               nbt.RootTag{
			name: ''
			tag:  nbt.Tag(nbt.new_compound())
		}
		blocks: []protocol.BlockEntry{}
	})!
	s.transport.send(&protocol.ItemRegistryPacket{
		entries: []types.ItemTypeEntry{}
	})!
	s.transport.send(&protocol.CreativeContentPacket{
		groups: []types.CreativeGroupEntry{}
		items:  []types.CreativeItemEntry{}
	})!
	s.transport.send(&protocol.BiomeDefinitionListPacket{
		biome_definitions: []protocol.BiomeDefinition{}
		string_list:       []string{}
	})!
	s.log.info('${s.identity.display_name} joined the game')
	s.state = .play
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
		block_position: types.BlockPosition{0, 64, 0}
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
	payload := empty_chunk_payload().bytestr()
	for x in -radius .. radius + 1 {
		for z in -radius .. radius + 1 {
			s.transport.queue(&protocol.LevelChunkPacket{
				chunk_position:  types.ChunkPosition{x, z}
				dimension_id:    0
				request_type:    protocol.level_chunk_request_explicit
				sub_chunk_count: 0
				cache_enabled:   false
				extra_payload:   payload
			})
		}
	}
	s.transport.flush()!
}

fn (mut s NetworkSession) handle_player_initialized(p protocol.SetLocalPlayerAsInitializedPacket) ! {
	s.log.info('${s.identity.display_name} spawned in the world')
}

fn gamemode_id(name string) int {
	return match name.to_lower() {
		'survival' { 0 }
		'adventure' { 2 }
		'spectator' { 6 }
		else { 1 }
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
