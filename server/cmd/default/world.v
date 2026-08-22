module default

import server.permission
import server.cmd

pub struct WorldCommand {}

pub fn (c WorldCommand) name() string {
	return 'world'
}

pub fn (c WorldCommand) description() string {
	return 'Manages worlds - list, info, metrics, create, load, delete, tp'
}

pub fn (c WorldCommand) aliases() []string {
	return ['worlds']
}

pub fn (c WorldCommand) permission() string {
	return permission.command_world
}

pub fn (c WorldCommand) arguments() []cmd.Argument {
	return [
		cmd.StringEnumArgument{
			arg_name: 'action'
			values:   ['list', 'info', 'metrics', 'create', 'load', 'delete', 'tp']
		},
		cmd.StringArgument{
			arg_name:     'name'
			arg_optional: true
		},
		cmd.StringEnumArgument{
			arg_name:     'dimension'
			values:       ['overworld', 'nether', 'end']
			arg_optional: true
		},
		cmd.StringArgument{
			arg_name:     'generator'
			arg_optional: true
		},
	]
}

pub fn (c WorldCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	if ctx.args.len == 0 {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	action := ctx.args[0].to_lower()
	match action {
		'list' {
			c.list(mut sender, ctx)!
		}
		'info' {
			c.info(mut sender, ctx)!
		}
		'metrics' {
			c.metrics(mut sender, ctx)!
		}
		'create' {
			c.create(mut sender, ctx)!
		}
		'load' {
			c.load(mut sender, ctx)!
		}
		'delete' {
			c.delete(mut sender, ctx)!
		}
		'tp' {
			c.teleport(mut sender, ctx)!
		}
		else {
			sender.send_message(ctx.lang.t('cmd.world.usage'))!
		}
	}
}

fn (c WorldCommand) list(mut sender cmd.Sender, ctx cmd.Context) ! {
	names := sender.world_names()
	if names.len == 0 {
		sender.send_message(ctx.lang.t('cmd.world.none'))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.world.list', {
		'Count':  names.len.str()
		'Worlds': names.join(', ')
	}))!
}

fn (c WorldCommand) info(mut sender cmd.Sender, ctx cmd.Context) ! {
	name := c.name_arg(ctx) or {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	info := sender.world_info(name) or {
		sender.send_message(ctx.lang.tf('cmd.world.not_found', {
			'Name': name
		}))!
		return
	}
	mut lines := []string{}
	lines << '§6World: §a${info.name}§r'
	lines << '§6Generator: §f${info.generator}§r'
	lines << '§6Dimension: §f${info.dimension}§r'
	lines << '§6Block overrides: §f${info.overrides}§r'
	lines << '§6Players: §f${info.players}§r'
	lines << '§6Default: §f${info.is_default}§r'
	sender.send_message(lines.join('\n'))!
}

fn (c WorldCommand) metrics(mut sender cmd.Sender, ctx cmd.Context) ! {
	name := c.name_arg(ctx) or {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	m := sender.world_metrics(name) or {
		sender.send_message(ctx.lang.tf('cmd.world.not_found', {
			'Name': name
		}))!
		return
	}
	mut lines := []string{}
	lines << '§6World: §a${m.name}§r'
	if !m.actor_running {
		lines << '§c§lACTOR STOPPED§r §7- this world is registered but rejects all work (a previous unload likely failed to close its storage handle; retry unloading it)§r'
	}
	lines << '§6Tick: §f${m.current_tick} (last tick §f${m.last_tick_duration_ms}ms§6, §f${m.catchup_events}§6 catch up runs, §f${m.tick_overruns}§6 overruns)§r'
	lines << '§6Queued tasks: §f${m.queued_tasks}§6 (oldest §f${m.oldest_queued_task_age_ms}ms§6)§r'
	lines << '§6Longest task: §f${m.longest_task_name} (§f${m.longest_task_duration_ms}ms§6)§r'
	lines << '§6Scheduled backlog: §f${m.scheduled_backlog}§6, liquid backlog: §f${m.liquid_backlog}§r'
	lines << '§6Entities: §f${m.entity_count}§6, players: §f${m.player_count}§r'
	lines << '§6Outbound overflows: §f${m.outbound_overflow_count}§6, peak queue depth: §f${m.outbound_peak_depth}§r'
	lines << '§6Persist backlog: §f${m.persist_pending_count}§6 pending (oldest §f${m.persist_oldest_pending_ms}ms§6), §f${m.persist_enqueued_total}§6 enqueued / §f${m.persist_committed_total}§6 committed total§r'
	lines << '§6Persist pressure: ${persist_pressure_label(m.persist_pressure_level)}§6 (high water §f${m.persist_high_water_threshold}§6, ceiling §f${m.persist_hard_ceiling_threshold}§6), §f${m.persist_consecutive_errors}§6 consecutive errors§r'
	lines << '§6Persist write time: §f${m.persist_last_write_ms}ms§6 last, §f${m.persist_longest_write_ms}ms§6 longest§r'
	lines << '§6Chunk service: §f${m.chunk_cached_count}§6 cached (~§f${format_chunk_bytes(m.chunk_cached_bytes)}§6/§f${format_chunk_bytes(m.chunk_cache_budget_bytes)}§6 budget), §f${m.chunk_active_workers}§6/§f${m.chunk_worker_limit}§6 workers busy, §f${m.chunk_queue_depth}§6 queued§r'
	lines << '§6Chunk requests: §f${m.chunk_requests_total}§6 total, §f${m.chunk_dedup_hits_total}§6 deduplicated, §f${m.chunk_inflight_count}§6 in flight (oldest §f${m.chunk_oldest_inflight_ms}ms§6)§r'
	sender.send_message(lines.join('\n'))!
}

fn format_chunk_bytes(total i64) string {
	if total < 1024 {
		return '${total} B'
	}
	mut value := f64(total)
	units := ['KiB', 'MiB', 'GiB']
	mut unit := units[0]
	for u in units {
		unit = u
		value /= 1024.0
		if value < 1024.0 {
			break
		}
	}
	return '${value:.1f} ${unit}'
}

fn persist_pressure_label(level int) string {
	return match level {
		2 { '§cCRITICAL§r' }
		1 { '§6HIGH WATER§r' }
		else { '§anormal§r' }
	}
}

fn (c WorldCommand) create(mut sender cmd.Sender, ctx cmd.Context) ! {
	name := c.name_arg(ctx) or {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	dimension := if ctx.args.len >= 3 && ctx.args[2].trim_space() != '' {
		ctx.args[2]
	} else {
		'overworld'
	}
	generator := if ctx.args.len >= 4 { ctx.args[3] } else { '' }
	sender.world_create(name, dimension, generator) or {
		sender.send_message(ctx.lang.tf('cmd.world.create_failed', {
			'Name':   name
			'Reason': err.msg()
		}))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.world.created', {
		'Name': name
	}))!
}

fn (c WorldCommand) load(mut sender cmd.Sender, ctx cmd.Context) ! {
	name := c.name_arg(ctx) or {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	sender.world_load(name) or {
		sender.send_message(ctx.lang.tf('cmd.world.load_failed', {
			'Name':   name
			'Reason': err.msg()
		}))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.world.loaded', {
		'Name': name
	}))!
}

fn (c WorldCommand) delete(mut sender cmd.Sender, ctx cmd.Context) ! {
	name := c.name_arg(ctx) or {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	sender.world_delete(name) or {
		sender.send_message(ctx.lang.tf('cmd.world.delete_failed', {
			'Name':   name
			'Reason': err.msg()
		}))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.world.deleted', {
		'Name': name
	}))!
}

fn (c WorldCommand) teleport(mut sender cmd.Sender, ctx cmd.Context) ! {
	if !sender.is_player() {
		sender.send_message(ctx.lang.t('cmd.player_only'))!
		return
	}
	name := c.name_arg(ctx) or {
		sender.send_message(ctx.lang.t('cmd.world.usage'))!
		return
	}
	sender.world_teleport(name) or {
		sender.send_message(ctx.lang.tf('cmd.world.tp_failed', {
			'Name':   name
			'Reason': err.msg()
		}))!
		return
	}
	sender.send_message(ctx.lang.tf('cmd.world.tp', {
		'Name': name
	}))!
}

// name_arg returns the second argument, or none when it's missing/blank.
fn (c WorldCommand) name_arg(ctx cmd.Context) ?string {
	if ctx.args.len < 2 || ctx.args[1].trim_space() == '' {
		return none
	}
	return ctx.args[1]
}
