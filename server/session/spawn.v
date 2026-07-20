module session

import math
import protocol
import protocol.enums
import protocol.types
import nbt
import server.event
import server.player.playerdb
import server.world
import server.world.db

const generated_chunk_cache_limit = 768
const chunk_send_batch_size = 4

struct ChunkSendTarget {
	x        int
	z        int
	distance int
	order    int
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

fn saved_body_clear(id int) bool {
	return id == world.air.network_id
}

fn saved_floor_solid(id int) bool {
	return id != world.air.network_id && id != world.water.network_id && id != world.lava.network_id
}

fn safe_player_position(gen world.Generator, pos types.Vector3) bool {
	feet_y := int(math.floor(f64(pos.y - player_eye_height)))
	x := int(math.floor(f64(pos.x)))
	z := int(math.floor(f64(pos.z)))
	return saved_floor_solid(gen.block_at(x, feet_y - 1, z))
		&& saved_body_clear(gen.block_at(x, feet_y, z))
		&& saved_body_clear(gen.block_at(x, feet_y + 1, z))
}

fn (mut s NetworkSession) start_game() ! {
	s.game_mode = gamemode_id(s.cfg.gamemode)
	spawn_y := s.generator.spawn_y()
	dimension_id := if isnil(s.world) { world.overworld.id } else { s.world.dimension.id }
	generator_type := if dimension_id == world.nether.id {
		protocol.world_generator_nether
	} else if dimension_id == world.the_end.id {
		protocol.world_generator_end
	} else {
		protocol.world_generator_overworld
	}
	s.position = types.Vector3{0.0, f32(spawn_y) + player_eye_height, 0.0}
	if data := playerdb.load_player(players_dir, s.player_key()) {
		saved_pos := types.Vector3{data.x, data.y, data.z}
		if safe_player_position(s.generator, saved_pos) {
			s.position = saved_pos
		}
		s.pitch = data.pitch
		s.yaw = data.yaw
		s.loaded_items = data.items
		s.game_mode = data.gamemode
		if data.has_last_death {
			s.has_last_death = true
			s.last_death_pos =
				types.Vector3{data.last_death_x, data.last_death_y, data.last_death_z}
		}
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
		dimension:                      dimension_id
		generator:                      generator_type
		world_game_mode:                s.game_mode
		difficulty:                     s.hub.difficulty
		world_spawn:                    types.BlockPosition{0, spawn_y, 0}
		commands_enabled:               true
		multi_player_game:              true
		server_chunk_tick_radius:       s.cfg.view_distance
		player_permissions:             if s.perm.op() {
			protocol.permission_level_operator
		} else {
			protocol.permission_level_member
		}
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
		blocks:                         s.custom_block_entries()
	})!
	if s.hub.custom_entities.len() > 0 {
		s.transport.send(&protocol.AvailableActorIdentifiersPacket{
			identifiers: s.hub.custom_entities.identifiers_nbt()
		})!
	}
	s.transport.send(s.item_registry())!
	s.transport.send(s.creative_content())!
	s.transport.send(&protocol.BiomeDefinitionListPacket{
		biome_definitions: []protocol.BiomeDefinition{}
		string_list:       []string{}
	})!
	s.transport.send(&protocol.SetDifficultyPacket{
		difficulty: s.hub.difficulty
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
	s.chunk_stream_mutex.lock()
	defer {
		s.chunk_stream_mutex.unlock()
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
	s.remember_chunk_window(radius)
	s.transport.send(&protocol.PlayStatusPacket{
		status: int(enums.PlayStatus.player_spawn)
	})!
	s.log.debug('Sent ${(radius * 2 + 1) * (radius * 2 + 1)} chunks to ${s.identity.display_name}')
}

fn should_stream_chunk_radius_async(state State, spawned bool) bool {
	return state == .play && spawned
}

fn (mut s NetworkSession) handle_play_chunk_radius_async(p protocol.RequestChunkRadiusPacket) {
	spawn s.handle_play_chunk_radius_background(p)
}

fn (mut s NetworkSession) handle_play_chunk_radius_background(p protocol.RequestChunkRadiusPacket) {
	s.handle_play_chunk_radius(p) or {
		s.log.warn('Failed to stream requested chunks to ${s.identity.display_name}: ${err}')
	}
}

fn (mut s NetworkSession) handle_play_chunk_radius(p protocol.RequestChunkRadiusPacket) ! {
	mut radius := p.radius
	if radius > s.cfg.view_distance {
		radius = s.cfg.view_distance
	}
	if radius < 1 {
		radius = 1
	}
	s.chunk_stream_mutex.lock()
	defer {
		s.chunk_stream_mutex.unlock()
	}
	cx := int(math.floor(f64(s.position.x))) >> 4
	cz := int(math.floor(f64(s.position.z))) >> 4
	old_radius := s.view_radius
	old_cx := s.last_chunk_x
	old_cz := s.last_chunk_z
	s.transport.send(&protocol.ChunkRadiusUpdatedPacket{
		radius: radius
	})!
	s.transport.send(&protocol.NetworkChunkPublisherUpdatePacket{
		block_position: types.BlockPosition{int(s.position.x), int(s.position.y), int(s.position.z)}
		radius:         radius * 16
		saved_chunks:   []types.ChunkPosition{}
	})!
	if old_radius <= 0 {
		s.send_needed_chunks(cx, cz, radius)!
	} else if cx != old_cx || cz != old_cz || radius > old_radius {
		s.send_needed_chunks(cx, cz, radius)!
	}
	s.remember_chunk_window(radius)
}

fn (mut s NetworkSession) stream_chunks_if_moved() {
	s.chunk_stream_mutex.lock()
	defer {
		s.chunk_stream_mutex.unlock()
	}
	if s.view_radius <= 0 {
		return
	}
	cx := int(math.floor(f64(s.position.x))) >> 4
	cz := int(math.floor(f64(s.position.z))) >> 4
	old_cx := s.last_chunk_x
	old_cz := s.last_chunk_z
	if cx == old_cx && cz == old_cz {
		return
	}
	s.last_chunk_x = cx
	s.last_chunk_z = cz
	s.transport.send(&protocol.NetworkChunkPublisherUpdatePacket{
		block_position: types.BlockPosition{int(s.position.x), int(s.position.y), int(s.position.z)}
		radius:         s.view_radius * 16
		saved_chunks:   []types.ChunkPosition{}
	}) or { return }
	s.send_needed_chunks(cx, cz, s.view_radius) or {}
}

fn (mut s NetworkSession) remember_chunk_window(radius int) {
	s.view_radius = radius
	s.last_chunk_x = int(math.floor(f64(s.position.x))) >> 4
	s.last_chunk_z = int(math.floor(f64(s.position.z))) >> 4
}

fn (mut s NetworkSession) reset_chunk_window() {
	s.chunk_stream_mutex.lock()
	s.view_radius = 0
	s.last_chunk_x = 0
	s.last_chunk_z = 0
	s.sent_chunks.clear()
	s.chunk_stream_mutex.unlock()
}

fn (mut s NetworkSession) send_spawn_chunks(radius int) ! {
	cx := int(math.floor(f64(s.position.x))) >> 4
	cz := int(math.floor(f64(s.position.z))) >> 4
	s.sent_chunks.clear()
	s.send_needed_chunks(cx, cz, radius)!
}

fn chunk_send_targets(cx int, cz int, radius int, sent map[u64]bool) []ChunkSendTarget {
	mut targets := []ChunkSendTarget{cap: (radius * 2 + 1) * (radius * 2 + 1)}
	span := radius * 2 + 1
	for x in cx - radius .. cx + radius + 1 {
		for z in cz - radius .. cz + radius + 1 {
			key := chunk_cache_key(x, z)
			if key in sent {
				continue
			}
			dx := x - cx
			dz := z - cz
			targets << ChunkSendTarget{
				x:        x
				z:        z
				distance: dx * dx + dz * dz
				order:    (dx * dx + dz * dz) * span * span + (x - (cx - radius)) * span +
					(z - (cz - radius))
			}
		}
	}
	targets.sort(a.order < b.order)
	return targets
}

fn prune_sent_chunks(mut sent map[u64]bool, cx int, cz int, radius int) {
	mut keep := map[u64]bool{}
	for x in cx - radius .. cx + radius + 1 {
		for z in cz - radius .. cz + radius + 1 {
			key := chunk_cache_key(x, z)
			if key in sent {
				keep[key] = true
			}
		}
	}
	sent.clear()
	for key, value in keep {
		sent[key] = value
	}
}

fn (mut s NetworkSession) send_needed_chunks(cx int, cz int, radius int) ! {
	wld, gen := s.world_and_generator()
	dim := if isnil(wld) { world.overworld } else { wld.dimension }
	prune_sent_chunks(mut s.sent_chunks, cx, cz, radius)
	targets := chunk_send_targets(cx, cz, radius, s.sent_chunks)
	mut batch := []protocol.Packet{cap: chunk_send_batch_size}
	mut batch_keys := []u64{cap: chunk_send_batch_size}
	for target in targets {
		mut chunk := s.generated_chunk(gen, target.x, target.z)
		apply_overrides(mut chunk, wld, target.x, target.z)
		batch << level_chunk_packet(dim, target.x, target.z, chunk)
		batch << tile_data_packets(wld, target.x, target.z)
		batch_keys << chunk_cache_key(target.x, target.z)
		if batch.len >= chunk_send_batch_size {
			s.transport.send_batch(batch)!
			for key in batch_keys {
				s.sent_chunks[key] = true
			}
			batch.clear()
			batch_keys.clear()
		}
	}
	if batch.len > 0 {
		s.transport.send_batch(batch)!
		for key in batch_keys {
			s.sent_chunks[key] = true
		}
	}
}

fn level_chunk_packet(dim world.Dimension, x int, z int, chunk world.Chunk) &protocol.LevelChunkPacket {
	return &protocol.LevelChunkPacket{
		chunk_position:  types.ChunkPosition{x, z}
		dimension_id:    dim.id
		request_type:    protocol.level_chunk_request_truncated
		sub_chunk_count: u32(chunk.section_count())
		cache_enabled:   false
		extra_payload:   chunk_biome_payload(dim, chunk).bytestr()
	}
}

fn chunk_biome_payload(dim world.Dimension, chunk world.Chunk) []u8 {
	biome := chunk.serialize_biomes()
	mut out := []u8{cap: biome.len * dim.subchunk_count + 1}
	for _ in 0 .. dim.subchunk_count {
		out << biome
	}
	out << 0
	return out
}

fn chunk_cache_key(cx int, cz int) u64 {
	return (u64(u32(cx)) << 32) | u64(u32(cz))
}

fn (mut s NetworkSession) clear_chunk_cache() {
	s.chunk_cache_mutex.lock()
	s.chunk_cache.clear()
	s.chunk_cache_mutex.unlock()
}

fn (mut s NetworkSession) generated_chunk(gen world.Generator, cx int, cz int) world.Chunk {
	key := chunk_cache_key(cx, cz)
	s.chunk_cache_mutex.lock()
	if chunk := s.chunk_cache[key] {
		s.chunk_cache_mutex.unlock()
		return chunk.clone()
	}
	s.chunk_cache_mutex.unlock()

	chunk := gen.generate(cx, cz)

	s.chunk_cache_mutex.lock()
	if s.chunk_cache.len >= generated_chunk_cache_limit {
		s.chunk_cache.clear()
	}
	s.chunk_cache[key] = chunk
	s.chunk_cache_mutex.unlock()
	return chunk.clone()
}

fn apply_overrides(mut chunk world.Chunk, wld &db.World, cx int, cz int) {
	if isnil(wld) {
		return
	}
	for ov in wld.overrides_in_chunk(cx, cz) {
		chunk.set_block(ov.x & 15, ov.y, ov.z & 15, world.block_from_id(ov.id))
	}
}

// tile_data_packets builds one BlockActorDataPacket per tile data entry
// (currently only sign text) in the given chunk column, so a freshly-loaded
// chunk shows existing sign text without waiting for a re-edit.
fn tile_data_packets(wld &db.World, cx int, cz int) []protocol.Packet {
	mut packets := []protocol.Packet{}
	if isnil(wld) {
		return packets
	}
	for entry in wld.tile_entries_in_chunk(cx, cz) {
		packets << &protocol.BlockActorDataPacket{
			block_position: types.BlockPosition{entry.x, entry.y, entry.z}
			nbt:            build_sign_nbt(entry.x, entry.y, entry.z, entry.text)
		}
	}
	return packets
}

const subchunk_result_success = u8(1)
const subchunk_result_invalid_dimension = u8(3)
const subchunk_result_index_out_of_bounds = u8(5)

fn subchunk_height_map(height_map []int, abs_index int) (u8, []i8) {
	section_min_y := abs_index * 16
	section_max_y := section_min_y + 15
	mut out := []i8{len: 256}
	mut all_too_high := true
	mut all_too_low := true
	for i, y in height_map {
		if y > section_max_y {
			out[i] = 16
			all_too_low = false
		} else if y < section_min_y {
			out[i] = -1
			all_too_high = false
		} else {
			out[i] = i8(y - section_min_y)
			all_too_high = false
			all_too_low = false
		}
	}
	if all_too_high {
		return protocol.subchunk_heightmap_all_too_high, []i8{}
	}
	if all_too_low {
		return protocol.subchunk_heightmap_all_too_low, []i8{}
	}
	return protocol.subchunk_heightmap_data, out
}

fn (mut s NetworkSession) handle_sub_chunk_request(p protocol.SubChunkRequestPacket) ! {
	wld, gen := s.world_and_generator()
	dim := if isnil(wld) { world.overworld } else { wld.dimension }
	if p.dimension != dim.id {
		mut entries := []protocol.SubChunkEntry{cap: p.entries.len}
		for off in p.entries {
			entries << protocol.SubChunkEntry{
				offset:         off
				request_result: subchunk_result_invalid_dimension
			}
		}
		s.transport.send(&protocol.SubChunkPacket{
			dimension:     p.dimension
			base_x:        p.base_x
			base_y:        p.base_y
			base_z:        p.base_z
			cache_enabled: false
			entries:       entries
		})!
		return
	}

	mut entries := []protocol.SubChunkEntry{cap: p.entries.len}
	mut height_cache := map[u64][]int{}
	mut tile_sent_columns := map[u64]bool{}
	for off in p.entries {
		target_cx := int(p.base_x) + int(off.x_offset)
		target_cz := int(p.base_z) + int(off.z_offset)
		abs_index := int(p.base_y) + int(off.y_offset)
		mut chunk := s.generated_chunk(gen, target_cx, target_cz)
		apply_overrides(mut chunk, wld, target_cx, target_cz)
		cache_key := chunk_cache_key(target_cx, target_cz)
		if cache_key !in tile_sent_columns {
			tile_sent_columns[cache_key] = true
			for pkt in tile_data_packets(wld, target_cx, target_cz) {
				s.transport.send(pkt) or {}
			}
		}
		height_map := height_cache[cache_key] or {
			heights := chunk.height_map()
			height_cache[cache_key] = heights
			heights
		}
		height_map_type, height_map_data := subchunk_height_map(height_map, abs_index)
		terrain := chunk.serialize_subchunk(abs_index) or {
			entries << protocol.SubChunkEntry{
				offset:         off
				request_result: subchunk_result_index_out_of_bounds
			}
			continue
		}
		entries << protocol.SubChunkEntry{
			offset:                 off
			request_result:         subchunk_result_success
			terrain_data:           terrain.bytestr()
			height_map_type:        height_map_type
			height_map:             height_map_data
			render_height_map_type: height_map_type
			render_height_map:      height_map_data
		}
	}
	s.transport.send(&protocol.SubChunkPacket{
		dimension:     p.dimension
		base_x:        p.base_x
		base_y:        p.base_y
		base_z:        p.base_z
		cache_enabled: false
		entries:       entries
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
	for e in s.hub.entities.snapshot() {
		s.deliver(e.spawn_packet())
	}
	s.hub.add(s)
	s.hub.broadcast(s.player_list_add_packet())
	s.hub.broadcast_except(s.runtime_id, s.add_player_packet())
	s.send_active_effects()
	mut ctx := event.new_context(event.JoinData{
		player:  s
		message: '§e${s.identity.display_name} joined the game'
	})
	s.hub.events.player_join(mut ctx)
	if !ctx.is_cancelled() && ctx.val.message != '' {
		s.hub.broadcast_message(ctx.val.message)
	}
	s.transport.send(s.restore_inventory())!
	s.refresh_available_commands()
	s.log.info('${s.identity.display_name} spawned in the world (${s.hub.count()} online)')
}

// refresh_available_commands resends the client's command list. The client
// only reads permission-gated visibility once (Command.execute checks it
// live, but the client-side autocomplete/menu does not) - anything that
// changes what s.perm can do after spawn (op/deop today, a future rank/VIP
// permission grant tomorrow) must call this or the player's command list
// stays stale until they reconnect.
pub fn (mut s NetworkSession) refresh_available_commands() {
	available := s.hub.commands.available_commands(s)
	s.transport.send(&available) or {}
}
