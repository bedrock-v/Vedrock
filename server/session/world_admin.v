module session

import bedrock_v.protocol.types
import server.cmd
import server.event
import server.world
import server.world.db
import server.player
import server.worldrt

// world_admin wires the /world command's needs onto the Hub. Create/delete
// only touch the worlds map (never a player's active world), so they run
// directly on the Hub which already guards that map. Teleport runs through
// change_world which transfers membership between the two owning world actors.

fn (mut s NetworkSession) world_names() []string {
	return s.hub.list_worlds()
}

fn (mut s NetworkSession) world_info(name string) ?cmd.WorldSummary {
	info := s.hub.world_info(name)?
	return to_world_summary(info)
}

fn (mut s NetworkSession) world_metrics(name string) ?cmd.WorldMetricsSummary {
	m := s.hub.world_metrics(name)?
	return to_world_metrics_summary(m)
}

fn (mut s NetworkSession) world_create(name string, dimension string, generator string) ! {
	dim := world.dimension_by_name(dimension) or {
		return error('unknown dimension "${dimension}"')
	}
	s.hub.create_world(name, dim, generator)!
	mut load_ctx := event.new_context(player.WorldLoadData{
		name:   name
		player: s
	})
	s.handler.on_world_load(mut load_ctx)
}

fn (mut s NetworkSession) world_load(name string) ! {
	s.hub.load_world(name)!
	mut ctx := event.new_context(player.WorldLoadData{
		name:   name
		player: s
	})
	s.handler.on_world_load(mut ctx)
}

fn (mut s NetworkSession) world_delete(name string) ! {
	mut ctx := event.new_context(player.WorldUnloadData{
		name:   name
		player: s
	})
	s.handler.on_world_unload(mut ctx)
	if ctx.is_cancelled() {
		return error('world deletion cancelled')
	}
	s.hub.delete_world(name)!
}

fn (mut s NetworkSession) world_teleport(name string) ! {
	target := s.hub.world(name) or { return error('world "${name}" is not loaded') }
	gen := target.make_generator(s.hub.build_generator(target))
	pos := world_spawn_position(target, gen)
	s.teleport_to_world(name, pos.x, pos.y, pos.z)
}

fn (mut c ConsoleSender) world_names() []string {
	return c.hub.list_worlds()
}

fn (mut c ConsoleSender) world_info(name string) ?cmd.WorldSummary {
	info := c.hub.world_info(name)?
	return to_world_summary(info)
}

fn (mut c ConsoleSender) world_metrics(name string) ?cmd.WorldMetricsSummary {
	m := c.hub.world_metrics(name)?
	return to_world_metrics_summary(m)
}

fn (mut c ConsoleSender) world_create(name string, dimension string, generator string) ! {
	dim := world.dimension_by_name(dimension) or {
		return error('unknown dimension "${dimension}"')
	}
	c.hub.create_world(name, dim, generator)!
	mut load_ctx := event.new_context(player.WorldLoadData{
		name:   name
		player: c
	})
	c.hub.player_handler.on_world_load(mut load_ctx)
}

fn (mut c ConsoleSender) world_load(name string) ! {
	c.hub.load_world(name)!
	mut ctx := event.new_context(player.WorldLoadData{
		name:   name
		player: c
	})
	c.hub.player_handler.on_world_load(mut ctx)
}

fn (mut c ConsoleSender) world_delete(name string) ! {
	mut ctx := event.new_context(player.WorldUnloadData{
		name:   name
		player: c
	})
	c.hub.player_handler.on_world_unload(mut ctx)
	if ctx.is_cancelled() {
		return error('world deletion cancelled')
	}
	c.hub.delete_world(name)!
}

fn (mut c ConsoleSender) world_teleport(_ string) ! {
	return error('the console cannot teleport into a world')
}

fn to_world_summary(info WorldInfo) cmd.WorldSummary {
	return cmd.WorldSummary{
		name:       info.name
		generator:  info.generator
		dimension:  info.dimension
		overrides:  info.overrides
		is_default: info.is_default
		players:    info.players
	}
}

fn to_world_metrics_summary(m worldrt.WorldMetrics) cmd.WorldMetricsSummary {
	return cmd.WorldMetricsSummary{
		name:                           m.world_name
		current_tick:                   m.current_tick
		requested_tick:                 m.requested_tick
		simulation_debt_ticks:          m.simulation_debt_ticks
		queued_tasks:                   m.queued_tasks
		oldest_queued_task_age_ms:      m.oldest_queued_task_age.milliseconds()
		last_tick_duration_ms:          m.last_tick_duration.milliseconds()
		longest_task_duration_ms:       m.longest_task_duration.milliseconds()
		longest_task_name:              m.longest_task_name
		catchup_events:                 m.catchup_events
		tick_overruns:                  m.tick_overruns
		scheduled_backlog:              m.scheduled_backlog
		liquid_backlog:                 m.liquid_backlog
		entity_count:                   m.entity_count
		player_count:                   m.player_count
		outbound_overflow_count:        m.outbound_overflow_count
		outbound_peak_depth:            m.outbound_peak_depth
		persist_pending_count:          m.persist_pending_count
		persist_oldest_pending_ms:      m.persist_oldest_pending_ms
		persist_enqueued_total:         m.persist_enqueued_total
		persist_committed_total:        m.persist_committed_total
		persist_pressure_level:         m.persist_pressure_level
		persist_high_water_threshold:   m.persist_high_water_threshold
		persist_hard_ceiling_threshold: m.persist_hard_ceiling_threshold
		persist_last_write_ms:          m.persist_last_write_ms
		persist_longest_write_ms:       m.persist_longest_write_ms
		persist_consecutive_errors:     m.persist_consecutive_errors
		chunk_cached_count:             m.chunk_cached_count
		chunk_cached_bytes:             m.chunk_cached_bytes
		chunk_cache_budget_bytes:       m.chunk_cache_budget_bytes
		chunk_inflight_count:           m.chunk_inflight_count
		chunk_oldest_inflight_ms:       m.chunk_oldest_inflight_ms
		chunk_active_workers:           m.chunk_active_workers
		chunk_worker_limit:             m.chunk_worker_limit
		chunk_queue_depth:              m.chunk_queue_depth
		chunk_requests_total:           m.chunk_requests_total
		chunk_dedup_hits_total:         m.chunk_dedup_hits_total
		actor_running:                  m.actor_running
	}
}

fn world_spawn_position(target &db.World, gen world.Generator) types.Vector3 {
	mut y := gen.spawn_y()
	if y < target.dimension.min_y + 1 {
		y = target.dimension.min_y + 1
	}
	max_y := target.dimension.max_y() - 1
	if y > max_y {
		y = max_y
	}
	return types.Vector3{0.0, f32(y) + player_eye_height, 0.0}
}
