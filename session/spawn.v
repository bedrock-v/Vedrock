module session

import math
import protocol
import protocol.enums
import protocol.types
import nbt
import storage
import world

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
	s.position = types.Vector3{0.0, f32(spawn_y) + player_eye_height, 0.0}
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
