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

fn roundtrip(p protocol.Packet) !protocol.Packet {
	mut pool := protocol.new_packet_pool()
	encoded := protocol.encode_packet_to_bytes(p)
	mut r := serializer.new_reader(encoded)
	return pool.decode(mut r)!
}

fn test_resource_packs_info_roundtrip() {
	decoded := roundtrip(&protocol.ResourcePacksInfoPacket{
		must_accept: false
		entries:     []protocol.ResourcePackInfoEntry{}
	})!
	assert decoded.name() == 'ResourcePacksInfoPacket'
}

fn test_resource_pack_stack_roundtrip() {
	decoded := roundtrip(&protocol.ResourcePackStackPacket{
		must_accept:         false
		resource_pack_stack: []protocol.ResourcePackStackEntry{}
		base_game_version:   protocol.minecraft_version_network
		experiments:         types.Experiments{}
	})!
	assert decoded.name() == 'ResourcePackStackPacket'
}

fn test_start_game_roundtrip() {
	decoded := roundtrip(&protocol.StartGamePacket{
		entity_unique_id:               1
		entity_runtime_id:              1
		player_game_mode:               1
		player_position:                types.Vector3{0.0, 64.0, 0.0}
		generator:                      1
		difficulty:                     1
		world_spawn:                    types.BlockPosition{0, 64, 0}
		commands_enabled:               true
		multi_player_game:              true
		base_game_version:              protocol.minecraft_version_network
		game_version:                   protocol.minecraft_version_network
		level_id:                       'Vedrock'
		world_name:                     'Vedrock Server'
		multi_player_correlation_id:    '00000000-0000-0000-0000-000000000000'
		server_authoritative_inventory: true
		property_data:                  nbt.RootTag{
			name: ''
			tag:  nbt.Tag(nbt.new_compound())
		}
		blocks:                         []protocol.BlockEntry{}
	})!
	assert decoded.name() == 'StartGamePacket'
	if decoded is protocol.StartGamePacket {
		assert decoded.world_name == 'Vedrock Server'
		assert decoded.game_version == protocol.minecraft_version_network
	} else {
		assert false
	}
}

fn first_start_game_packet(transport &FakeTransport) ?protocol.StartGamePacket {
	for p in transport.sent {
		if p is protocol.StartGamePacket {
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
	assert pkt.use_block_network_id_hashes
}

fn test_accepts_saved_pos_supported_by_world_overr() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_saved_override_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut hub := new_hub(gamedata.GameData{})
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
		gamemode: protocol.game_type_survival
	}) or { panic('save failed: ${err}') }
	mut transport := &FakeTransport{}
	mut s := start_game_test_session(mut hub, mut transport, target, world.VoidGenerator{}, conf.Config{
		players_dir: dir
	})

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
	assert map_type == protocol.subchunk_heightmap_data
	assert data.len == 256
	assert data[0] == 3
	assert data[255] == 3
}

fn test_subchunk_height_map_reports_all_too_low() {
	flat := world.FlatGenerator{}
	chunk := flat.generate(0, 0)
	height_map := chunk.height_map()
	map_type, data := subchunk_height_map(height_map, world.overworld.min_y / 16 + 1)
	assert map_type == protocol.subchunk_heightmap_all_too_low
	assert data.len == 0
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

fn test_level_chunk_packet_uses_subchunk_request_mode() {
	chunk := world.FlatGenerator{}.generate(0, 0)
	packet := level_chunk_packet(world.overworld, 0, 0, chunk)
	assert packet.request_type == protocol.level_chunk_request_truncated
	assert packet.sub_chunk_count == u32(chunk.section_count())
	payload := packet.extra_payload.bytes()
	assert payload.len == world.overworld.subchunk_count * 2 + 1
	assert payload[0] != 9
	assert payload[payload.len - 1] == 0
}

fn test_registry_packets_roundtrip() {
	assert roundtrip(&protocol.ItemRegistryPacket{
		entries: []types.ItemTypeEntry{}
	})!.name() == 'ItemRegistryPacket'
	assert roundtrip(&protocol.CreativeContentPacket{
		groups: []types.CreativeGroupEntry{}
		items:  []types.CreativeItemEntry{}
	})!.name() == 'CreativeContentPacket'
	assert roundtrip(&protocol.BiomeDefinitionListPacket{
		biome_definitions: []protocol.BiomeDefinition{}
		string_list:       []string{}
	})!.name() == 'BiomeDefinitionListPacket'
}
