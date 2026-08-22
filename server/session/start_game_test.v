module session

import protocol

import protocol.types
import protocol.serializer
import nbt
import os
import sync
import server.conf
import server.internal.auth
import server.internal.gamedata
import server.internal.logger
import server.player
import server.player.playerdb
import server.world
import server.world.db
import protocol.current as proto

fn roundtrip(p protocol.Packet) !protocol.Packet {
	mut pool := proto.new_packet_pool()
	encoded := protocol.encode_packet_to_bytes(p)
	mut r := serializer.new_reader(encoded)
	return pool.decode(mut r)!
}

// decode_into reads a packet's payload back into a typed value. The pool builds
// the type the version module declares, which an alias of it does not stand in
// for, so the fields are read back directly instead of through a type check.
fn decode_into[T](p protocol.Packet, mut out T) ! {
	mut r := serializer.new_reader(protocol.encode_packet_to_bytes(p))
	protocol.read_packet_header(mut r)!
	out.decode_payload(mut r)!
}

fn test_resource_packs_info_roundtrip() {
	decoded := roundtrip(&proto.ResourcePacksInfoPacket{
		resource_pack_required:        false
		has_addon_packs:               false
		has_scripts:                   false
		force_disable_vibrant_visuals: false
		world_template_uuid:           proto.uuid_from_bytes([]u8{len: 16})
		world_template_version:        ''
		resource_packs:                []proto.ResourcePackEntry{}
	})!
	assert decoded.name() == 'ResourcePacksInfoPacket'
}

fn test_resource_pack_stack_roundtrip() {
	decoded := roundtrip(&proto.ResourcePackStackPacket{
		texture_pack_required: false
		addon_list:            []proto.PackEntry{}
		base_game_version:     proto.BaseGameVersion{
			value: proto.selected_minecraft_version
		}
		experiments:           proto.Experiments{}
		include_editor_packs:  false
	})!
	assert decoded.name() == 'ResourcePackStackPacket'
}

fn test_start_game_roundtrip() {
	mut start := &proto.StartGamePacket{
		target_actor_id:               proto.actor_unique_id(1)
		target_runtime_id:             proto.actor_runtime_id(1)
		actor_game_type:               proto.GameType.survival
		settings:                      proto.LevelSettings{
			seed:                                         0
			spawn_settings:                               proto.SpawnSettings{
				spawn_type:              proto.SpawnBiomeType.default
				user_defined_biome_name: ''
				dimension:               0
			}
			generator_type:                               proto.GeneratorType.overworld
			game_type:                                    proto.GameType.survival
			game_difficulty:                              proto.Difficulty.normal
			default_spawn_block_position:                 proto.NetworkBlockPosition{
				x: 0
				y: 64
				z: 0
			}
			achievements_disabled:                        true
			editor_world_type:                            proto.EditorWorldType.non_editor
			day_cycle_stop_time:                          -1
			education_edition_offer:                      proto.education_edition_offer_none
			multiplayer_enabled:                          true
			lan_broadcasting_enabled:                     true
			xbox_live_broadcast_setting:                  proto.GamePublishSetting.public
			platform_broadcast_setting:                   proto.GamePublishSetting.public
			commands_enabled:                             true
			rule_data:                                    proto.GameRuleLegacyData{}
			experiments:                                  proto.Experiments{}
			player_permissions:                           u8(proto.PlayerPermissionLevel.member)
			server_chunk_tick_range:                      4
			base_game_version:                            proto.BaseGameVersion{
				value: proto.selected_minecraft_version
			}
			edu_shared_uri_resource:                      proto.EduSharedUriResource{}
			override_force_experimental_gameplay:         false
			chat_restriction_level:                       proto.ChatRestrictionLevel.@none
			allow_anonymous_block_drops_in_editor_worlds: false
		}
		level_id:                      'Vedrock'
		level_name:                    'Vedrock Server'
		movement_settings:             proto.SyncedPlayerMovementSettings{
			server_authoritative_block_breaking: true
		}
		multiplayer_correlation_id:    '00000000-0000-0000-0000-000000000000'
		enable_item_stack_net_manager: true
		server_version:                proto.selected_minecraft_version
		player_property_data:          nbt.RootTag{
			name: ''
			tag:  nbt.Tag(nbt.new_compound())
		}
		world_template_id:             proto.uuid_from_bytes([]u8{len: 16})
		block_network_ids_are_hashes:  true
		network_permissions:           proto.NetworkPermissions{}
	}
	start.position[0] = 0.0
	start.position[1] = 64.0
	start.position[2] = 0.0
	assert roundtrip(start)!.name() == 'StartGamePacket'
	mut decoded := proto.StartGamePacket{}
	decode_into(start, mut decoded)!
	assert decoded.level_name == 'Vedrock Server'
	assert decoded.server_version == proto.selected_minecraft_version
}

fn first_start_game_packet(transport &FakeTransport) ?proto.StartGamePacket {
	for p in transport.sent {
		if p is proto.StartGamePacket {
			return p
		}
	}
	return none
}

fn start_game_test_session(mut hub Hub, mut transport FakeTransport, target &db.World, gen world.Generator, cfg conf.Config) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	return &NetworkSession{
		player:        pl
		runtime_id:    1
		transport:     transport
		hub:           hub
		cfg:           cfg
		world:         target
		world_runtime: hub.world_runtime(target.name) or { panic('expected world runtime') }
		generator:     gen
		log:           logger.new(.info)
	}
}

fn test_always_advertises_block_hash_runtime_ids() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('void', none, 'void', world.overworld)
	hub.add_world(target)
	defer {
		hub.close_worlds()
	}
	mut transport := &FakeTransport{}
	mut s :=
		start_game_test_session(mut hub, mut transport, target, world.VoidGenerator{}, conf.Config{})

	s.start_game()!

	pkt := first_start_game_packet(transport) or {
		assert false, 'missing StartGamePacket'
		return
	}
	assert pkt.block_network_ids_are_hashes
}

fn test_accepts_saved_pos_supported_by_world_overr() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_saved_override_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut hub := new_hub(gamedata.GameData{},
		player_data_provider: playerdb.FileProvider{
			dir: dir
		}
	)
	target := db.new_world('void', none, 'void', world.overworld)
	hub.add_world(target)
	target.set_block(0, 10, 0, world.bedrock.network_id)
	defer {
		hub.close_worlds()
	}
	playerdb.save_player(dir, 'Alex', playerdb.PlayerData{
		x:        0.5
		y:        f32(11) + player_eye_height
		z:        0.5
		gamemode: proto.game_type_survival
	}) or { panic('save failed: ${err}') }
	mut transport := &FakeTransport{}
	mut s :=
		start_game_test_session(mut hub, mut transport, target, world.VoidGenerator{}, conf.Config{})

	s.start_game()!

	assert s.player.position().y == f32(11) + player_eye_height
}

fn test_saved_player_position_must_be_standable() {
	flat := world.FlatGenerator{}
	flat_spawn := types.Vector3{0.0, f32(flat.spawn_y()) + player_eye_height, 0.0}
	assert safe_player_position(flat, flat_spawn)
	assert !safe_player_position(flat, types.Vector3{0.0, f32(world.overworld.min_y + 2), 0.0})

	nether := world.NetherGenerator{}
	nether_spawn := types.Vector3{0.0, f32(nether.spawn_y()) + player_eye_height, 0.0}
	assert safe_player_position(nether, nether_spawn)
	assert !safe_player_position(nether, types.Vector3{0.0, 4.0 + player_eye_height, 0.0})
}

fn test_world_spawn_position_uses_target_world_generator() {
	target := db.new_world('nether', none, 'nether', world.nether)
	gen := world.NetherGenerator{}
	pos := world_spawn_position(target, gen)
	assert pos.x == 0.0
	assert pos.z == 0.0
	assert pos.y == f32(gen.spawn_y()) + player_eye_height
	assert pos.y != 64.0
}

fn test_chunk_radius_streams_async_only_after_player_spawn() {
	assert !should_stream_chunk_radius_async(.login, false)
	assert !should_stream_chunk_radius_async(.resource_packs, false)
	assert !should_stream_chunk_radius_async(.play, false)
	assert should_stream_chunk_radius_async(.play, true)
}

fn test_subchunk_height_map_reports_relative_height() {
	flat := world.FlatGenerator{}
	chunk := flat.generate(0, 0)
	height_map := chunk.height_map()
	map_type, data := subchunk_height_map(height_map, world.overworld.min_y / 16)
	assert map_type == proto.HeightMapDataType.has_data
	// The map is one flat slot per column, indexed z * 16 + x.
	assert data[0] == 3
	assert data[15 * 16 + 15] == 3
}

fn test_subchunk_height_map_reports_all_too_low() {
	flat := world.FlatGenerator{}
	chunk := flat.generate(0, 0)
	height_map := chunk.height_map()
	map_type, data := subchunk_height_map(height_map, world.overworld.min_y / 16 + 1)
	assert map_type == proto.HeightMapDataType.all_too_low
	assert data[0] == 0
}

struct CountingGenerator {
	counter &GenerateCounter = unsafe { nil }
}

struct GenerateCounter {
mut:
	count int
	mutex &sync.Mutex = sync.new_mutex()
}

fn (g CountingGenerator) spawn_y() int {
	return 64
}

fn (g CountingGenerator) uses_blocks() bool {
	return true
}

fn (g CountingGenerator) generate(chunk_x int, chunk_z int) world.Chunk {
	mut counter := g.counter
	counter.mutex.lock()
	counter.count++
	counter.mutex.unlock()
	mut chunk := world.new_chunk_dim(world.nether)
	chunk.set_block(0, 0, 0, world.bedrock)
	return chunk
}

fn (g CountingGenerator) block_at(x int, y int, z int) int {
	return world.air.network_id
}

fn (g CountingGenerator) biome_at(x int, z int) int {
	return world.biome_hell
}

fn test_generated_chunk_cache_reuses_chunk_columns() {
	mut counter := &GenerateCounter{
		mutex: sync.new_mutex()
	}
	gen := CountingGenerator{
		counter: counter
	}
	mut s := &NetworkSession{
		chunk_cache_mutex: sync.new_mutex()
	}
	_ := s.generated_chunk(gen, 4, -2)
	_ := s.generated_chunk(gen, 4, -2)
	counter.mutex.lock()
	assert counter.count == 1
	counter.mutex.unlock()
}

fn test_generated_chunk_cache_returns_mutable_copies() {
	mut counter := &GenerateCounter{
		mutex: sync.new_mutex()
	}
	gen := CountingGenerator{
		counter: counter
	}
	mut s := &NetworkSession{
		chunk_cache_mutex: sync.new_mutex()
	}
	mut first := s.generated_chunk(gen, 4, -2)
	first.set_block(0, 0, 0, world.air)
	second := s.generated_chunk(gen, 4, -2)
	assert second.block_id(0, 0, 0) == world.bedrock.network_id
}

fn test_prune_sent_chunks_keeps_only_current_radius() {
	mut sent := map[u64]bool{}
	sent[chunk_cache_key(0, 0)] = true
	sent[chunk_cache_key(1, 0)] = true
	sent[chunk_cache_key(4, 0)] = true
	prune_sent_chunks(mut sent, 1, 0, 1)
	assert sent[chunk_cache_key(0, 0)]
	assert sent[chunk_cache_key(1, 0)]
	assert chunk_cache_key(4, 0) !in sent
}

fn test_level_chunk_packet_sends_sections_inline() {
	chunk := world.FlatGenerator{}.generate(0, 0)
	packet := level_chunk_packet(world.overworld, 0, 0, chunk)
	assert packet.sub_chunk_count == u32(chunk.section_count())
	assert packet.client_request_sub_chunk_limit == none
	assert !packet.cache_enabled
	assert packet.serialized_chunk_data.len > 0
	assert packet.serialized_chunk_data[packet.serialized_chunk_data.len - 1] == 0
}

fn test_registry_packets_roundtrip() {
	assert roundtrip(&proto.ItemComponentPacket{
		items: []proto.ItemsEntry{}
	})!.name() == 'ItemComponentPacket'
	assert roundtrip(&proto.CreativeContentPacket{
		groups:   []proto.CreativeItemGroup{}
		contents: []proto.CreativeItemData{}
	})!.name() == 'CreativeContentPacket'
	assert roundtrip(&proto.BiomeDefinitionListPacket{
		biomes:  []proto.BiomeEntry{}
		strings: []string{}
	})!.name() == 'BiomeDefinitionListPacket'
}
