module session

import math
import time
import protocol
import protocol.version.v662.enums as enums_662
import protocol.version.v662.packets as packets_662
import protocol.version.v662.types as types_662
import protocol.version.v776.packets as packets_776
import protocol.version.v818.types as types_818
import protocol.version.v944.types as types_944
import protocol.version.v944.packets as packets_944
import protocol.version.v1001.packets as packets_1001
import protocol.version.v2168.types as types_2168
import protocol.version.v2168.packets as packets_2168
import protocol.types
import nbt
import server.event
import server.internal.network
import server.world
import server.world.db

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

fn (mut s NetworkSession) start_game() ! {
	s.player.set_game_mode(gamemode_id(s.cfg.gamemode))
	spawn_y := s.generator.spawn_y()
	dimension_id := if isnil(s.world) { world.overworld.id } else { s.world.dimension.id }
	generator_type := if dimension_id == world.nether.id {
		enums_662.GeneratorType.nether
	} else if dimension_id == world.the_end.id {
		enums_662.GeneratorType.the_end
	} else {
		enums_662.GeneratorType.overworld
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
		enums_662.PlayerPermissionLevel.operator
	} else {
		enums_662.PlayerPermissionLevel.member
	}
	mut start_packet := &packets_2168.StartGamePacket{
		target_actor_id:                       network.actor_unique_id(i64(s.runtime_id))
		target_runtime_id:                     network.actor_runtime_id(s.runtime_id)
		actor_game_type:                       network.game_type(s.player.game_mode())
		settings:                              types_2168.LevelSettings{
			seed:                                         0
			spawn_settings:                               types_662.SpawnSettings{
				spawn_type:              enums_662.SpawnBiomeType.default
				user_defined_biome_name: ''
				dimension:               i32(dimension_id)
			}
			generator_type:                               generator_type
			game_type:                                    network.game_type(s.player.game_mode())
			is_hardcore_enabled:                          false
			game_difficulty:                              unsafe { enums_662.Difficulty(s.hub.difficulty_value()) }
			default_spawn_block_position:                 types_944.NetworkBlockPosition{
				x: 0
				y: i32(spawn_y)
				z: 0
			}
			achievements_disabled:                        false
			editor_world_type:                            enums_662.EditorWorldType.non_editor
			is_created_in_editor:                         false
			is_exported_from_editor:                      false
			day_cycle_stop_time:                          0
			education_edition_offer:                      enums_662.EducationEditionOffer.@none
			education_features_enabled:                   false
			education_product_id:                         ''
			rain_level:                                   0
			lightning_level:                              0
			has_confirmed_platform_locked_content:        false
			multiplayer_enabled:                          true
			lan_broadcasting_enabled:                     false
			xbox_live_broadcast_setting:                  enums_662.GamePublishSetting.no_multi_play
			platform_broadcast_setting:                   enums_662.GamePublishSetting.no_multi_play
			commands_enabled:                             true
			texture_packs_required:                       false
			rule_data:                                    types_2168.GameRuleLegacyData{}
			experiments:                                  types_662.Experiments{}
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
			base_game_version:                            types_662.BaseGameVersion{
				value: network.selected_minecraft_version
			}
			limited_world_width:                          0
			limited_world_depth:                          0
			nether_type:                                  dimension_id == world.nether.id
			edu_shared_uri_resource:                      types_662.EduSharedUriResource{}
			override_force_experimental_gameplay:         none
			chat_restriction_level:                       enums_662.ChatRestrictionLevel.@none
			disable_player_interactions:                  false
			server_editor_connection_policy:              0
			allow_anonymous_block_drops_in_editor_worlds: false
		}
		level_id:                              'Vedrock'
		level_name:                            s.cfg.motd
		template_content_identity:             ''
		is_trial:                              false
		movement_settings:                     types_818.SyncedPlayerMovementSettings{
			server_authoritative_block_breaking: true
		}
		current_level_time:                    0
		enchantment_seed:                      0
		block_properties:                      s.custom_block_entries()
		multiplayer_correlation_id:            '00000000-0000-0000-0000-000000000000'
		enable_item_stack_net_manager:         true
		server_version:                        network.selected_minecraft_version
		player_property_data:                  nbt.RootTag{
			name: ''
			tag:  nbt.Tag(nbt.new_compound())
		}
		server_block_type_registry_checksum:   0
		world_template_id:                     network.uuid_from_bytes([]u8{len: 16})
		server_enabled_client_side_generation: false
		block_network_ids_are_hashes:          true
		network_permissions:                   types_662.NetworkPermissions{}
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
	// The client builds its collision registry from this while it reads the
	// level, so it goes out ahead of StartGame. The server defines no custom
	// shapes, but the packet itself is not optional.
	s.transport.send(&packets_2168.VoxelShapesPacket{})!
	s.transport.send(start_packet)!
	s.transport.send(s.item_registry())!
	// Sent unconditionally: the client resolves its own player actor against
	// this list, so the actor data below has nothing to attach to without it.
	s.transport.send(&packets_662.AvailableActorIdentifiersPacket{
		actor_info_list: s.entity_identifiers()
	})!
	s.transport.send(s.creative_content())!
	s.transport.send(biome_definition_list())!
	s.transport.send(&packets_662.SetDifficultyPacket{
		difficulty: u32(s.hub.difficulty_value())
	})!
	s.transport.send(&packets_776.UpdateAbilitiesPacket{
		data: s.build_abilities_776()
	})!
	s.transport.send(adventure_settings())!
	s.transport.send(s.update_attributes())!
	s.transport.send(s.set_actor_data())!
	s.log.info('${s.player.identity.display_name} joined the game')
	s.state = .play
	if s.pending_radius > 0 {
		radius := s.pending_radius
		s.pending_radius = 0
		s.handle_request_chunk_radius(packets_662.RequestChunkRadiusPacket{ chunk_radius: radius })!
	}
}

fn (mut s NetworkSession) handle_request_chunk_radius(p packets_662.RequestChunkRadiusPacket) ! {
	mut radius := p.chunk_radius
	if radius > s.cfg.view_distance {
		radius = s.cfg.view_distance
	}
	if radius < 1 {
		radius = 1
	}
	own := s.player.position()
	s.transport.send(&packets_662.ChunkRadiusUpdatedPacket{
		chunk_radius: radius
	})!
	s.transport.send(&packets_662.NetworkChunkPublisherUpdatePacket{
		new_view_position:   types_662.BlockPos{
			x: i32(own.x)
			y: i32(own.y)
			z: i32(own.z)
		}
		new_view_radius:     u32(radius * 16)
		server_built_chunks: []types_662.ChunkPos{}
	})!
	s.transport.send(&packets_662.PlayStatusPacket{
		status: enums_662.PlayStatus.player_spawn
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

fn (mut s NetworkSession) handle_play_chunk_radius_async(p packets_662.RequestChunkRadiusPacket) {
	spawn s.handle_play_chunk_radius_background(p)
}

fn (mut s NetworkSession) handle_play_chunk_radius_background(p packets_662.RequestChunkRadiusPacket) {
	s.handle_play_chunk_radius(p) or {
		s.log.warn('Failed to stream requested chunks to ${s.player.identity.display_name}: ${err}')
	}
}

fn (mut s NetworkSession) handle_play_chunk_radius(p packets_662.RequestChunkRadiusPacket) ! {
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
	s.send_packet(&packets_662.ChunkRadiusUpdatedPacket{
		chunk_radius: radius
	})!
	s.send_packet(&packets_662.NetworkChunkPublisherUpdatePacket{
		new_view_position:   types_662.BlockPos{
			x: i32(own.x)
			y: i32(own.y)
			z: i32(own.z)
		}
		new_view_radius:     u32(radius * 16)
		server_built_chunks: []types_662.ChunkPos{}
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

	s.send_packet(&packets_662.NetworkChunkPublisherUpdatePacket{
		new_view_position:   types_662.BlockPos{
			x: i32(own.x)
			y: i32(own.y)
			z: i32(own.z)
		}
		new_view_radius:     u32(radius * 16)
		server_built_chunks: []types_662.ChunkPos{}
	}) or {
		s.forget_sent_chunks(claimed)
		return
	}
	if targets.len == 0 {
		return
	}
	// Only allow one generation batch per session at a time. If one is
	// already running, defer this batch to a later tick.
	if !s.chunk_gen_mutex.try_lock() {
		s.forget_sent_chunks(claimed)
		return
	}
	mut active_gen := s.hub.active_chunk_generation_count
	active_gen.add(1)
	binding := s.world_binding()
	spawn s.generate_and_deliver_chunks(binding, targets)
}

// generate_and_deliver_chunks builds and encodes the requested columns away
// from the world thread, using the world binding captured when they were
// scheduled.
//
// Concurrent block edits are not version checked here because their own
// UpdateBlockPacket broadcasts correct any stale column data afterward.
//
// Holds chunk_gen_mutex for its entire run, released via defer regardless
// of how it returns.
fn (mut s NetworkSession) generate_and_deliver_chunks(binding WorldBinding, targets []ChunkSendTarget) {
	defer {
		s.chunk_gen_mutex.unlock()
		mut active_gen := s.hub.active_chunk_generation_count
		active_gen.sub(1)
	}
	dim := if isnil(binding.world) { world.overworld } else { binding.world.dimension }
	chans := s.request_chunk_channels(binding.world_runtime, targets)
	mut batch := []protocol.Packet{cap: chunk_send_batch_size}
	mut batch_keys := []u64{cap: chunk_send_batch_size}
	for i, target in targets {
		result := resolve_chunk_result(chans[i])
		batch << chunk_delivery_packet_from_result(result, binding.world, dim, target.x, target.z)
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
	binding := s.world_binding()
	wld := binding.world
	dim := if isnil(wld) { world.overworld } else { wld.dimension }
	prune_sent_chunks(mut s.sent_chunks, cx, cz, radius)
	targets := chunk_send_targets(cx, cz, radius, s.sent_chunks)
	chans := s.request_chunk_channels(binding.world_runtime, targets)
	mut batch := []protocol.Packet{cap: chunk_send_batch_size}
	mut batch_keys := []u64{cap: chunk_send_batch_size}
	for i, target in targets {
		result := resolve_chunk_result(chans[i])
		batch << chunk_delivery_packet_from_result(result, wld, dim, target.x, target.z)
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
fn level_chunk_packet(dim world.Dimension, x int, z int, chunk world.Chunk) &packets_2168.LevelChunkPacket {
	return &packets_2168.LevelChunkPacket{
		chunk_position:                 types_662.ChunkPos{
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

// level_chunk_packet_from_bytes builds the same packet as
// level_chunk_packet but from an already-serialized column.
fn level_chunk_packet_from_bytes(dim world.Dimension, x int, z int, section_count int, serialized []u8) &packets_2168.LevelChunkPacket {
	return &packets_2168.LevelChunkPacket{
		chunk_position:                 types_662.ChunkPos{
			x: i32(x)
			z: i32(z)
		}
		dimension_id:                   dim.id
		sub_chunk_count:                u32(section_count)
		client_request_sub_chunk_limit: none
		cache_enabled:                  false
		serialized_chunk_data:          serialized
	}
}

fn chunk_cache_key(cx int, cz int) u64 {
	return (u64(u32(cx)) << 32) | u64(u32(cz))
}

// empty_chunk_result returns a valid empty ChunkResult for unavailable or
// cancelled chunk requests. It uses an initialized empty chunk rather than
// ChunkResult's zero value whose sections are not sized for the dimension
// and are unsafe for downstream indexed access.
fn empty_chunk_result() ChunkResult {
	empty := world.new_chunk()
	return ChunkResult{
		chunk:         empty
		serialized:    empty.serialize()
		section_count: empty.section_count()
	}
}

// generated_chunk resolves (cx, cz) through the world's shared chunk service
// rather than generating or caching the chunk per session.
fn (mut s NetworkSession) generated_chunk(wr &WorldRuntime, cx int, cz int) world.Chunk {
	return s.generated_chunk_result(wr, cx, cz).chunk
}

// generated_chunk_result resolves one chunk through the world's shared chunk
// service and includes its cached serialized bytes and section count.
//
// This call blocks until that column is ready. For a view radius sweep, use
// request_chunk_channels/resolve_chunk_result so multiple columns can be
// resolved concurrently instead of serializing the sweep one column at a time.
fn (mut s NetworkSession) generated_chunk_result(wr &WorldRuntime, cx int, cz int) ChunkResult {
	if isnil(wr) {
		return empty_chunk_result()
	}
	mut svc := wr.chunk_service
	result := <-svc.request(cx, cz)
	if result.cancelled {
		return empty_chunk_result()
	}
	return result
}

// request_chunk_channels submits all target chunk requests up front and
// returns their result channels without waiting for generation.
//
// This preserves the chunk service's worker concurrency across a radius
// sweep. Requesting and awaiting each column sequentially would serialize
// the sweep one chunk at a time.
fn (mut s NetworkSession) request_chunk_channels(wr &WorldRuntime, targets []ChunkSendTarget) []chan ChunkResult {
	mut chans := []chan ChunkResult{cap: targets.len}
	if isnil(wr) {
		for _ in targets {
			ch := chan ChunkResult{cap: 1}
			ch <- empty_chunk_result()
			chans << ch
		}
		return chans
	}
	mut svc := wr.chunk_service
	for target in targets {
		chans << svc.request(target.x, target.z)
	}
	return chans
}

// resolve_chunk_result drains one channel from request_chunk_channels,
// normalizing a cancelled result the same way generated_chunk_result does
// for a single request.
fn resolve_chunk_result(ch chan ChunkResult) ChunkResult {
	result := <-ch
	if result.cancelled {
		return empty_chunk_result()
	}
	return result
}

// chunk_delivery_packet_from_result builds a LevelChunkPacket from an
// already resolved ChunkResult.
//
// If the chunk has no block overrides, it reuses the cached serialized
// bytes. Otherwise it applies the current overrides and serializes a fresh
// chunk so preoverride bytes are never sent for modified terrain.
fn chunk_delivery_packet_from_result(result ChunkResult, wld &db.World, dim world.Dimension, cx int, cz int) protocol.Packet {
	overrides := if isnil(wld) { []db.BlockOverride{} } else { wld.overrides_in_chunk(cx, cz) }
	if overrides.len == 0 {
		return level_chunk_packet_from_bytes(dim, cx, cz, result.section_count, result.serialized)
	}
	mut chunk := result.chunk
	apply_overrides_list(mut chunk, overrides)
	return level_chunk_packet(dim, cx, cz, chunk)
}

// chunk_delivery_packet resolves a single chunk and builds its packet.
//
// For a view radius sweep, use the pipelined chunk request path instead so
// multiple columns can be resolved concurrently by the chunk worker pool.
fn (mut s NetworkSession) chunk_delivery_packet(wr &WorldRuntime, wld &db.World, dim world.Dimension, cx int, cz int) protocol.Packet {
	result := s.generated_chunk_result(wr, cx, cz)
	return chunk_delivery_packet_from_result(result, wld, dim, cx, cz)
}

fn apply_overrides_list(mut chunk world.Chunk, overrides []db.BlockOverride) {
	for ov in overrides {
		chunk.set_block(ov.x & 15, ov.y, ov.z & 15, world.block_from_id(ov.id))
	}
}

fn apply_overrides(mut chunk world.Chunk, wld &db.World, cx int, cz int) {
	if isnil(wld) {
		return
	}
	apply_overrides_list(mut chunk, wld.overrides_in_chunk(cx, cz))
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
		packets << &packets_944.BlockActorDataPacket{
			block_position:  network.block_pos_v944(types.BlockPosition{entry.x, entry.y, entry.z})
			actor_data_tags: build_sign_nbt(entry.x, entry.y, entry.z, entry.text)
		}
	}
	return packets
}

fn subchunk_center(pos [3]i32) types_2168.SubChunkPos {
	return types_2168.SubChunkPos{
		x: pos[0]
		y: pos[1]
		z: pos[2]
	}
}

fn subchunk_height_map(height_map []int, abs_index int) (packets_2168.HeightMapDataType, [16][16]i8) {
	section_min_y := abs_index * 16
	section_max_y := section_min_y + 15
	mut out := [16][16]i8{}
	mut all_too_high := true
	mut all_too_low := true
	for i, y in height_map {
		x := i / 16
		z := i % 16
		if y > section_max_y {
			out[x][z] = 16
			all_too_low = false
		} else if y < section_min_y {
			out[x][z] = -1
			all_too_high = false
		} else {
			out[x][z] = i8(y - section_min_y)
			all_too_high = false
			all_too_low = false
		}
	}
	if all_too_high {
		return packets_2168.HeightMapDataType.all_too_high, [16][16]i8{}
	}
	if all_too_low {
		return packets_2168.HeightMapDataType.all_too_low, [16][16]i8{}
	}
	return packets_2168.HeightMapDataType.has_data, out
}

// handle_sub_chunk_request may run before outbound activation because
// SubChunkRequestPacket is accepted in play state without requiring spawn.
fn (mut s NetworkSession) handle_sub_chunk_request(p packets_1001.SubChunkRequestPacket) ! {
	binding := s.world_binding()
	wld := binding.world
	dim := if isnil(wld) { world.overworld } else { wld.dimension }
	if p.dimension_type != dim.id {
		mut entries := []packets_2168.SubChunkDataEntry{cap: p.sub_chunk_pos_offsets.len}
		for off in p.sub_chunk_pos_offsets {
			entries << packets_2168.SubChunkDataEntry{
				sub_chunk_pos_offset:     off
				sub_chunk_request_result: .wrong_dimension
			}
		}
		s.send_maybe_queued(&packets_2168.SubChunkPacket{
			cache_enabled:  false
			dimension_type: p.dimension_type
			center_pos:     subchunk_center(p.center_pos)
			sub_chunk_data: entries
		})!
		return
	}

	mut entries := []packets_2168.SubChunkDataEntry{cap: p.sub_chunk_pos_offsets.len}
	mut height_cache := map[u64][]int{}
	mut tile_sent_columns := map[u64]bool{}
	for off in p.sub_chunk_pos_offsets {
		target_cx := int(p.center_pos[0]) + int(off.offset_x)
		target_cz := int(p.center_pos[2]) + int(off.offset_z)
		abs_index := int(p.center_pos[1]) + int(off.offset_y)
		mut chunk := s.generated_chunk(binding.world_runtime, target_cx, target_cz)
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
			entries << packets_2168.SubChunkDataEntry{
				sub_chunk_pos_offset:     off
				sub_chunk_request_result: .index_out_of_bounds
			}
			continue
		}
		entries << packets_2168.SubChunkDataEntry{
			sub_chunk_pos_offset:        off
			sub_chunk_request_result:    .success
			serialized_sub_chunk:        terrain
			height_map_data_type:        height_map_type
			height_map_data:             height_map_data
			render_height_map_data_type: height_map_type
			render_height_map_data:      height_map_data
		}
	}
	s.send_maybe_queued(&packets_2168.SubChunkPacket{
		cache_enabled:  false
		dimension_type: p.dimension_type
		center_pos:     subchunk_center(p.center_pos)
		sub_chunk_data: entries
	})!
}

fn (mut s NetworkSession) handle_player_initialized(_ packets_662.SetLocalPlayerAsInitializedPacket) ! {
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
		self := s.self_ref()
		deliver_packets := world_call[[]protocol.Packet](mut wr, fn [self, list_add_pkt, add_player_pkt] (mut tx WorldTx) []protocol.Packet {
			mut out := []protocol.Packet{}
			for a in tx.wr.entities.player_actors() {
				if a is NetworkSession {
					out << a.player_list_add_packet()
					out << a.add_player_packet()
				}
			}
			tx.register_player(self)
			tx.wr.broadcast_world(list_add_pkt)
			tx.wr.broadcast_world_except(self.runtime_id, add_player_pkt)
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
