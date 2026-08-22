module session

import math
import time
import protocol

import protocol.types
import nbt
import server.event
import server.world
import server.world.db
import protocol.current as proto

const generated_chunk_cache_limit = 768
// The initial spawn stream paces itself so the outbound queue is not filled
// faster than the writer drains it. A radius 8 view is 289 columns, so the
// pause per batch dominates how long the world takes to appear.
const chunk_send_batch_size = 8
const chunk_batch_pace = 10 * time.millisecond

struct ChunkSendTarget {
	x        int
	z        int
	distance int
	order    int
}

// player_key picks the save file identity: xuid, then uuid, then
// display_name. xuid/uuid are only trusted when xbox_authenticated.
// both fields are populated from client-supplied JWT claims regardless
// of whether the chain actually verified, an unauthenticated claim must
// never resolve to the same key a real Xbox authenticated player would get.
fn (mut s NetworkSession) player_key() string {
	if s.player.identity.xbox_authenticated {
		if s.player.identity.xuid != '' {
			return s.player.identity.xuid
		}
		if s.player.identity.uuid != '' {
			return s.player.identity.uuid
		}
	}
	return s.player.identity.display_name
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

fn saved_position_block_at(wld &db.World, gen world.Generator, x int, y int, z int) int {
	if !isnil(wld) {
		if id := wld.block_override(x, y, z) {
			return id
		}
	}
	return gen.block_at(x, y, z)
}

fn safe_player_position_in_world(wld &db.World, gen world.Generator, pos types.Vector3) bool {
	feet_y := int(math.floor(f64(pos.y - player_eye_height)))
	x := int(math.floor(f64(pos.x)))
	z := int(math.floor(f64(pos.z)))
	return saved_floor_solid(saved_position_block_at(wld, gen, x, feet_y - 1, z))
		&& saved_body_clear(saved_position_block_at(wld, gen, x, feet_y, z))
		&& saved_body_clear(saved_position_block_at(wld, gen, x, feet_y + 1, z))
}

// jigsaw_structure_data is the jigsaw registry the client reads before
// StartGame. The server defines no jigsaw structures, but the four lists have
// to be there for the client to find them empty rather than missing.
fn jigsaw_structure_data() &proto.JigsawStructureDataPacket {
	mut root := nbt.new_compound()
	for key in ['processors', 'template_pools', 'jigsaws', 'structure_sets'] {
		root.set(key, nbt.Tag(nbt.List{
			element_type: nbt.tag_compound
		}))
	}
	return &proto.JigsawStructureDataPacket{
		jigsaw_structure_data_tag: nbt.RootTag{
			name: ''
			tag:  nbt.Tag(root)
		}
	}
}

fn (mut s NetworkSession) start_game() ! {
	s.player.set_game_mode(gamemode_id(s.cfg.gamemode))
	spawn_y := s.generator.spawn_y()
	dimension_id := if isnil(s.world) { world.overworld.id } else { s.world.dimension.id }
	generator_type := if dimension_id == world.nether.id {
		proto.GeneratorType.nether
	} else if dimension_id == world.the_end.id {
		proto.GeneratorType.the_end
	} else {
		proto.GeneratorType.overworld
	}
	mut spawn_pos := types.Vector3{0.0, f32(spawn_y) + player_eye_height, 0.0}
	mut spawn_pitch := f32(0.0)
	mut spawn_yaw := f32(0.0)
	if data := s.hub.player_data_provider.load(s.player_key()) {
		saved_pos := types.Vector3{data.x, data.y, data.z}
		if safe_player_position_in_world(s.world, s.generator, saved_pos) {
			spawn_pos = saved_pos
		}
		spawn_pitch = data.pitch
		spawn_yaw = data.yaw
		s.player.set_loaded_items(data.items)
		s.player.set_game_mode(data.gamemode)
		if data.has_last_death {
			s.player.set_last_death(types.Vector3{data.last_death_x, data.last_death_y, data.last_death_z})
		}
	}
	s.player.reset_position(spawn_pos)
	s.player.set_orientation(spawn_pitch, spawn_yaw, spawn_yaw)
	player_permission := if s.player.perm.op() {
		proto.PlayerPermissionLevel.operator
	} else {
		proto.PlayerPermissionLevel.member
	}
	mut start_packet := &proto.StartGamePacket{
		target_actor_id:                       proto.actor_unique_id(i64(s.runtime_id))
		target_runtime_id:                     proto.actor_runtime_id(s.runtime_id)
		actor_game_type:                       proto.game_type(s.player.game_mode())
		settings:                              proto.LevelSettings{
			seed:                                         0
			spawn_settings:                               proto.SpawnSettings{
				spawn_type:              proto.SpawnBiomeType.default
				user_defined_biome_name: ''
				dimension:               i32(dimension_id)
			}
			generator_type:                               generator_type
			game_type:                                    proto.game_type(s.player.game_mode())
			is_hardcore_enabled:                          false
			game_difficulty:                              unsafe { proto.Difficulty(s.hub.difficulty_value()) }
			default_spawn_block_position:                 proto.NetworkBlockPosition{
				x: 0
				y: i32(spawn_y)
				z: 0
			}
			achievements_disabled:                        false
			editor_world_type:                            proto.EditorWorldType.non_editor
			is_created_in_editor:                         false
			is_exported_from_editor:                      false
			day_cycle_stop_time:                          0
			education_edition_offer:                      proto.education_edition_offer_none
			education_features_enabled:                   false
			education_product_id:                         ''
			rain_level:                                   0
			lightning_level:                              0
			has_confirmed_platform_locked_content:        false
			multiplayer_enabled:                          true
			lan_broadcasting_enabled:                     false
			xbox_live_broadcast_setting:                  proto.GamePublishSetting.no_multi_play
			platform_broadcast_setting:                   proto.GamePublishSetting.no_multi_play
			commands_enabled:                             true
			texture_packs_required:                       false
			rule_data:                                    proto.GameRuleLegacyData{}
			experiments:                                  proto.Experiments{}
			bonus_chest_enabled:                          false
			starting_map_enabled:                         false
			player_permissions:                           u8(player_permission)
			server_chunk_tick_range:                      s.cfg.view_distance
			locked_behaviour_pack:                        false
			locked_resource_pack:                         false
			from_locked_template:                         false
			use_msa_gamer_tags:                           false
			from_template:                                false
			has_locked_template_settings:                 false
			only_spawn_v1_villagers:                      false
			persona_disabled:                             false
			custom_skins_disabled:                        false
			emote_chat_muted:                             false
			base_game_version:                            proto.BaseGameVersion{
				value: proto.selected_minecraft_version
			}
			limited_world_width:                          0
			limited_world_depth:                          0
			nether_type:                                  dimension_id == world.nether.id
			edu_shared_uri_resource:                      proto.EduSharedUriResource{}
			override_force_experimental_gameplay:         none
			chat_restriction_level:                       proto.ChatRestrictionLevel.@none
			disable_player_interactions:                  false
			server_editor_connection_policy:              0
			allow_anonymous_block_drops_in_editor_worlds: false
		}
		level_id:                              'Vedrock'
		level_name:                            s.cfg.motd
		template_content_identity:             ''
		is_trial:                              false
		movement_settings:                     proto.SyncedPlayerMovementSettings{
			server_authoritative_block_breaking: true
		}
		current_level_time:                    0
		enchantment_seed:                      0
		block_properties:                      s.custom_block_entries()
		multiplayer_correlation_id:            '00000000-0000-0000-0000-000000000000'
		enable_item_stack_net_manager:         true
		server_version:                        proto.selected_minecraft_version
		player_property_data:                  nbt.RootTag{
			name: ''
			tag:  nbt.Tag(nbt.new_compound())
		}
		server_block_type_registry_checksum:   0
		world_template_id:                     proto.uuid_from_bytes([]u8{len: 16})
		server_enabled_client_side_generation: false
		block_network_ids_are_hashes:          true
		network_permissions:                   proto.NetworkPermissions{}
		server_join_information:               none
		server_id:                             ''
		world_id:                              ''
		scenario_id:                           ''
		owner_id:                              ''
	}
	start_packet.position[0] = spawn_pos.x
	start_packet.position[1] = spawn_pos.y
	start_packet.position[2] = spawn_pos.z
	start_packet.rotation[0] = spawn_pitch
	start_packet.rotation[1] = spawn_yaw
	s.transport.send(jigsaw_structure_data())!
	// The client builds its collision registry from this while it reads the
	// level, so it goes out ahead of StartGame. Only the vanilla shapes are
	// sent, but the client still resolves them by the names carried here.
	s.transport.send(s.voxel_shapes())!
	s.transport.send(start_packet)!
	s.transport.send(s.item_registry())!
	// Sent unconditionally: the client resolves its own player actor against
	// this list, so the actor data below has nothing to attach to without it.
	s.transport.send(&proto.AvailableActorIdentifiersPacket{
		actor_info_list: s.entity_identifiers()
	})!
	s.transport.send(s.creative_content())!
	s.transport.send(biome_definition_list())!
	s.transport.send(&proto.SetDifficultyPacket{
		difficulty: u32(s.hub.difficulty_value())
	})!
	s.transport.send(&proto.UpdateAbilitiesPacket{
		data: s.build_abilities()
	})!
	s.transport.send(adventure_settings())!
	s.transport.send(s.update_attributes())!
	s.transport.send(s.set_actor_data())!
	s.log.info('${s.player.identity.display_name} joined the game')
	s.state = .play
	if s.pending_radius > 0 {
		radius := s.pending_radius
		s.pending_radius = 0
		s.handle_request_chunk_radius(proto.RequestChunkRadiusPacket{ chunk_radius: radius })!
	}
}

fn (mut s NetworkSession) handle_request_chunk_radius(p proto.RequestChunkRadiusPacket) ! {
	mut radius := p.chunk_radius
	if radius > s.cfg.view_distance {
		radius = s.cfg.view_distance
	}
	if radius < 1 {
		radius = 1
	}
	own := s.player.position()
	s.transport.send(&proto.ChunkRadiusUpdatedPacket{
		chunk_radius: radius
	})!
	s.transport.send(&proto.NetworkChunkPublisherUpdatePacket{
		new_view_position:   proto.BlockPos{
			x: i32(own.x)
			y: i32(own.y)
			z: i32(own.z)
		}
		new_view_radius:     u32(radius * 16)
		server_built_chunks: []proto.ChunkPos{}
	})!
	s.transport.send(&proto.PlayStatusPacket{
		status: proto.PlayStatus.player_spawn
	})!
	spawn s.stream_spawn_chunks_background(radius)
}

fn (mut s NetworkSession) stream_spawn_chunks_background(radius int) {
	s.chunk_stream_mutex.lock()
	defer {
		s.chunk_stream_mutex.unlock()
	}
	s.send_spawn_chunks(radius) or {
		s.log.debug('Initial chunk stream to ${s.player.identity.display_name} ended: ${err}')
		return
	}
	s.remember_chunk_window(radius)
	s.log.debug('Sent ${(radius * 2 + 1) * (radius * 2 + 1)} chunks to ${s.player.identity.display_name}')
}

fn should_stream_chunk_radius_async(state State, spawned bool) bool {
	return state == .play && spawned
}

fn (mut s NetworkSession) handle_play_chunk_radius_async(p proto.RequestChunkRadiusPacket) {
	spawn s.handle_play_chunk_radius_background(p)
}

fn (mut s NetworkSession) handle_play_chunk_radius_background(p proto.RequestChunkRadiusPacket) {
	s.handle_play_chunk_radius(p) or {
		s.log.warn('Failed to stream requested chunks to ${s.player.identity.display_name}: ${err}')
	}
}

fn (mut s NetworkSession) handle_play_chunk_radius(p proto.RequestChunkRadiusPacket) ! {
	mut radius := p.chunk_radius
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
	own := s.player.position()
	cx := int(math.floor(f64(own.x))) >> 4
	cz := int(math.floor(f64(own.z))) >> 4
	old_radius := s.view_radius
	old_cx := s.last_chunk_x
	old_cz := s.last_chunk_z
	s.send_packet(&proto.ChunkRadiusUpdatedPacket{
		chunk_radius: radius
	})!
	s.send_packet(&proto.NetworkChunkPublisherUpdatePacket{
		new_view_position:   proto.BlockPos{
			x: i32(own.x)
			y: i32(own.y)
			z: i32(own.z)
		}
		new_view_radius:     u32(radius * 16)
		server_built_chunks: []proto.ChunkPos{}
	})!
	if old_radius <= 0 {
		s.send_needed_chunks(cx, cz, radius)!
	} else if cx != old_cx || cz != old_cz || radius > old_radius {
		s.send_needed_chunks(cx, cz, radius)!
	}
	s.remember_chunk_window(radius)
}

// stream_chunks_if_moved checks whether movement crossed into a new chunk
// column, then sends the required columns to the generation worker so the
// world thread is not held up by chunk generation.
fn (mut s NetworkSession) stream_chunks_if_moved() {
	if !s.chunk_stream_mutex.try_lock() {
		return
	}
	if s.view_radius <= 0 {
		s.chunk_stream_mutex.unlock()
		return
	}
	own := s.player.position()
	cx := int(math.floor(f64(own.x))) >> 4
	cz := int(math.floor(f64(own.z))) >> 4
	old_cx := s.last_chunk_x
	old_cz := s.last_chunk_z
	if cx == old_cx && cz == old_cz {
		s.chunk_stream_mutex.unlock()
		return
	}
	s.last_chunk_x = cx
	s.last_chunk_z = cz
	radius := s.view_radius
	prune_sent_chunks(mut s.sent_chunks, cx, cz, radius)
	targets := chunk_send_targets(cx, cz, radius, s.sent_chunks)
	// Claim the columns before releasing the lock so a second movement event
	// does not queue them again. Anything that fails to reach the client from
	// here on has to be released again, or the column stays a hole until the
	// player leaves and re-enters the view radius.
	mut claimed := []u64{cap: targets.len}
	for target in targets {
		key := chunk_cache_key(target.x, target.z)
		claimed << key
		s.sent_chunks[key] = true
	}
	s.chunk_stream_mutex.unlock()

	s.send_packet(&proto.NetworkChunkPublisherUpdatePacket{
		new_view_position:   proto.BlockPos{
			x: i32(own.x)
			y: i32(own.y)
			z: i32(own.z)
		}
		new_view_radius:     u32(radius * 16)
		server_built_chunks: []proto.ChunkPos{}
	}) or {
		s.forget_sent_chunks(claimed)
		return
	}
	if targets.len == 0 {
		return
	}
	binding := s.world_binding()
	spawn s.generate_and_deliver_chunks(binding, targets)
}

// generate_and_deliver_chunks builds and encodes the requested columns away
// from the world thread, using the world binding captured when they were
// scheduled.
//
// Concurrent block edits are not version checked here because their own
// UpdateBlockPacket broadcasts correct any stale column data afterward.
fn (mut s NetworkSession) generate_and_deliver_chunks(binding WorldBinding, targets []ChunkSendTarget) {
	dim := if isnil(binding.world) { world.overworld } else { binding.world.dimension }
	mut batch := []protocol.Packet{cap: chunk_send_batch_size}
	mut batch_keys := []u64{cap: chunk_send_batch_size}
	for target in targets {
		mut chunk := s.generated_chunk(binding.generator, target.x, target.z)
		apply_overrides(mut chunk, binding.world, target.x, target.z)
		batch << level_chunk_packet(dim, target.x, target.z, chunk)
		batch << tile_data_packets(binding.world, target.x, target.z)
		batch_keys << chunk_cache_key(target.x, target.z)
		if batch_keys.len >= chunk_send_batch_size {
			if !s.commit_chunk_batch(binding, batch.clone()) {
				s.forget_sent_chunks(batch_keys)
			}
			batch.clear()
			batch_keys.clear()
		}
	}
	if batch.len > 0 && !s.commit_chunk_batch(binding, batch.clone()) {
		s.forget_sent_chunks(batch_keys)
	}
}

// forget_sent_chunks releases columns claimed by stream_chunks_if_moved that
// never reached the client, so the next movement into range retries them.
fn (mut s NetworkSession) forget_sent_chunks(keys []u64) {
	s.chunk_stream_mutex.lock()
	for key in keys {
		s.sent_chunks.delete(key)
	}
	s.chunk_stream_mutex.unlock()
}

// commit_chunk_batch returns generated columns to their original world.
// The world thread delivers them only if the same player is still
// registered under the captured epoch.
//
// Columns that have since moved outside the player's view radius may still
// be sent; this wastes bandwidth but does not send incorrect world data.
//
// Returns false when the batch could not be queued at all, which is the
// caller's cue to release the columns for a later retry.
fn (mut s NetworkSession) commit_chunk_batch(binding WorldBinding, batch []protocol.Packet) bool {
	if isnil(binding.world_runtime) {
		return false
	}
	mut wr := binding.world_runtime
	return wr.try_submit(ChunkDeliveryTask{
		runtime_id: s.runtime_id
		epoch:      binding.epoch
		packets:    batch
	})
}

// ChunkDeliveryTask validates a generated chunk batch against the player's
// captured world binding, then queues it for delivery. Chunk streaming only
// runs for spawned players, so normal send_batch is sufficient here.
struct ChunkDeliveryTask {
	runtime_id u64
	epoch      i64
	packets    []protocol.Packet
}

fn (t ChunkDeliveryTask) name() string {
	return 'ChunkDeliveryTask'
}

fn (t ChunkDeliveryTask) run(mut tx WorldTx) {
	mut s := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	s.send_batch(t.packets) or {}
}

fn (mut s NetworkSession) remember_chunk_window(radius int) {
	own := s.player.position()
	s.view_radius = radius
	s.last_chunk_x = int(math.floor(f64(own.x))) >> 4
	s.last_chunk_z = int(math.floor(f64(own.z))) >> 4
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
	own := s.player.position()
	cx := int(math.floor(f64(own.x))) >> 4
	cz := int(math.floor(f64(own.z))) >> 4
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

// send_needed_chunks runs during both bootstrap and normal play, so it
// chooses direct or queued batch delivery from the session's current phase.
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
		if batch_keys.len >= chunk_send_batch_size {
			s.send_batch_maybe_queued(batch)!
			for key in batch_keys {
				s.sent_chunks[key] = true
			}
			batch.clear()
			batch_keys.clear()
			time.sleep(chunk_batch_pace)
		}
	}
	if batch.len > 0 {
		s.send_batch_maybe_queued(batch)!
		for key in batch_keys {
			s.sent_chunks[key] = true
		}
	}
}

// level_chunk_packet sends every section inline. Truncated mode, where only
// biome data goes inline and the client pulls sections with
// SubChunkRequestPacket, leaves it without the terrain it needs to spawn.
fn level_chunk_packet(dim world.Dimension, x int, z int, chunk world.Chunk) &proto.LevelChunkPacket {
	return &proto.LevelChunkPacket{
		chunk_position:                 proto.ChunkPos{
			x: i32(x)
			z: i32(z)
		}
		dimension_id:                   dim.id
		sub_chunk_count:                u32(chunk.section_count())
		client_request_sub_chunk_limit: none
		cache_enabled:                  false
		serialized_chunk_data:          chunk.serialize()
	}
}

fn chunk_cache_key(cx int, cz int) u64 {
	return (u64(u32(cx)) << 32) | u64(u32(cz))
}

fn (mut s NetworkSession) clear_chunk_cache() {
	s.chunk_cache_mutex.lock()
	s.chunk_cache.clear()
	s.chunk_cache_mutex.unlock()
}

// generated_chunk returns the column to send. A bound world caches it for the
// whole server, so the block reads that decide what a player is mining see the
// same terrain this sent.
fn (mut s NetworkSession) generated_chunk(gen world.Generator, cx int, cz int) world.Chunk {
	mut wld := s.current_world()
	if !isnil(wld) {
		return wld.generated_chunk(gen, cx, cz).clone()
	}
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
		packets << &proto.BlockActorDataPacket{
			block_position:  proto.block_pos(types.BlockPosition{entry.x, entry.y, entry.z})
			actor_data_tags: build_sign_nbt(entry.x, entry.y, entry.z, entry.text)
		}
	}
	return packets
}

fn subchunk_center(pos [3]i32) proto.SubChunkPos {
	return proto.SubChunkPos{
		x: pos[0]
		y: pos[1]
		z: pos[2]
	}
}

fn subchunk_height_map(height_map []int, abs_index int) (proto.HeightMapDataType, [272]i8) {
	section_min_y := abs_index * 16
	section_max_y := section_min_y + 15
	mut out := [272]i8{}
	mut all_too_high := true
	mut all_too_low := true
	for i, y in height_map {
		x := i / 16
		z := i % 16
		slot := z * 16 + x
		if y > section_max_y {
			out[slot] = 16
			all_too_low = false
		} else if y < section_min_y {
			out[slot] = -1
			all_too_high = false
		} else {
			out[slot] = i8(y - section_min_y)
			all_too_high = false
			all_too_low = false
		}
	}
	if all_too_high {
		return proto.HeightMapDataType.all_too_high, [272]i8{}
	}
	if all_too_low {
		return proto.HeightMapDataType.all_too_low, [272]i8{}
	}
	return proto.HeightMapDataType.has_data, out
}

// handle_sub_chunk_request may run before outbound activation because
// SubChunkRequestPacket is accepted in play state without requiring spawn.
fn (mut s NetworkSession) handle_sub_chunk_request(p proto.SubChunkRequestPacket) ! {
	wld, gen := s.world_and_generator()
	dim := if isnil(wld) { world.overworld } else { wld.dimension }
	if p.dimension_type != dim.id {
		mut entries := []proto.SubChunkDataEntry{cap: p.sub_chunk_pos_offsets.len}
		for off in p.sub_chunk_pos_offsets {
			entries << proto.SubChunkDataEntry{
				sub_chunk_pos_offset:     off
				sub_chunk_request_result: .wrong_dimension
			}
		}
		s.send_maybe_queued(&proto.SubChunkPacket{
			cache_enabled:  false
			dimension_type: p.dimension_type
			center_pos:     subchunk_center(p.center_pos)
			sub_chunk_data: entries
		})!
		return
	}

	mut entries := []proto.SubChunkDataEntry{cap: p.sub_chunk_pos_offsets.len}
	mut height_cache := map[u64][]int{}
	mut tile_sent_columns := map[u64]bool{}
	for off in p.sub_chunk_pos_offsets {
		target_cx := int(p.center_pos[0]) + int(off.offset_x)
		target_cz := int(p.center_pos[2]) + int(off.offset_z)
		abs_index := int(p.center_pos[1]) + int(off.offset_y)
		mut chunk := s.generated_chunk(gen, target_cx, target_cz)
		apply_overrides(mut chunk, wld, target_cx, target_cz)
		cache_key := chunk_cache_key(target_cx, target_cz)
		if cache_key !in tile_sent_columns {
			tile_sent_columns[cache_key] = true
			for pkt in tile_data_packets(wld, target_cx, target_cz) {
				s.send_maybe_queued(pkt) or {}
			}
		}
		height_map := height_cache[cache_key] or {
			heights := chunk.height_map()
			height_cache[cache_key] = heights
			heights
		}
		height_map_type, height_map_data := subchunk_height_map(height_map, abs_index)
		terrain := chunk.serialize_subchunk(abs_index) or {
			entries << proto.SubChunkDataEntry{
				sub_chunk_pos_offset:     off
				sub_chunk_request_result: .index_out_of_bounds
			}
			continue
		}
		entries << proto.SubChunkDataEntry{
			sub_chunk_pos_offset:        off
			sub_chunk_request_result:    .success
			serialized_sub_chunk:        terrain
			height_map_data_type:        height_map_type
			height_map_data:             height_map_data
			render_height_map_data_type: height_map_type
			render_height_map_data:      height_map_data
		}
	}
	s.send_maybe_queued(&proto.SubChunkPacket{
		cache_enabled:  false
		dimension_type: p.dimension_type
		center_pos:     subchunk_center(p.center_pos)
		sub_chunk_data: entries
	})!
}

fn (mut s NetworkSession) handle_player_initialized(_ proto.SetLocalPlayerAsInitializedPacket) ! {
	if s.spawned {
		return
	}
	s.spawned = true
	// Must run before anything below: the world_call right after this
	// registers the session and broadcasts back to it from the world
	// actor thread, before hub.add ever runs. That's the real first point
	// this session becomes reachable by another thread, not hub.add and
	// not the .play state change (bootstrap sends and chunk streaming
	// still happen directly, before this function runs).
	//
	// A false return means the session already started closing. Stop
	// here rather than registering a closing session into a world or Hub.
	if !s.activate_outbound() {
		return
	}
	mut wr := s.current_world_runtime()
	if !isnil(wr) {
		// Initial membership, existing player enumeration and join broadcasts
		// share one world actor call. Existing players are collected before
		// registration so the joining player is never included in its own list.
		// Later transfers use change_world's deregister/rebind/register path.
		list_add_pkt := s.player_list_add_packet()
		add_player_pkt := s.add_player_packet()
		deliver_packets := world_call[[]protocol.Packet](mut wr, fn [s, list_add_pkt, add_player_pkt] (mut tx WorldTx) []protocol.Packet {
			mut out := []protocol.Packet{}
			for a in tx.wr.entities.player_actors() {
				if a is NetworkSession {
					out << a.player_list_add_packet()
					out << a.add_player_packet()
				}
			}
			tx.register_player(s)
			tx.wr.broadcast_world(list_add_pkt)
			tx.wr.broadcast_world_except(s.runtime_id, add_player_pkt)
			for e in tx.wr.entities.snapshot() {
				out << e.spawn_packet()
			}
			return out
		}) or { []protocol.Packet{} }
		for pkt in deliver_packets {
			s.deliver(pkt)
		}
	}
	s.hub.add(s)
	if !isnil(wr) {
		s.send_active_effects(mut wr)
	}
	mut ctx := event.new_context(event.JoinData{
		player:  s
		message: '§e${s.player.identity.display_name} joined the game'
	})
	s.hub.events.player_join(mut ctx)
	if !ctx.is_cancelled() && ctx.val.message != '' {
		s.hub.broadcast_message(ctx.val.message)
	}
	inventory_packet := s.restore_inventory()
	s.send_packet(inventory_packet)!
	s.refresh_available_commands()
	s.log.info('${s.player.identity.display_name} spawned in the world (${s.hub.count()} online)')
}

// refresh_available_commands rebuilds and resends the client's command
// list. The client only reads permission visibility once, so anything
// that changes what s.player.perm can do after spawn must call this, or
// the list stays stale until reconnect. Queued because permission changes
// may come from the owning world thread.
fn (mut s NetworkSession) refresh_available_commands() {
	available := s.hub.commands.available_commands(s)
	s.deliver(available)
}
