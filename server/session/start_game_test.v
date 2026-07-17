module session

import protocol
import protocol.types
import protocol.serializer
import nbt
import sync
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
	target := db.new_world('nether', unsafe { nil }, 'nether', world.nether)
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
