module default

import server.permission
import server.cmd

pub struct StatusCommand {}

pub fn (c StatusCommand) name() string {
	return 'status'
}

pub fn (c StatusCommand) description() string {
	return 'Gets the current status of the server'
}

pub fn (c StatusCommand) aliases() []string {
	return ['stats']
}

pub fn (c StatusCommand) permission() string {
	return permission.command_status
}

pub fn (c StatusCommand) arguments() []cmd.Argument {
	return []
}

pub fn (c StatusCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	tps_color := tps_format_color(ctx.tps)
	mut lines := []string{}
	lines << ctx.lang.t('cmd.status.header')
	lines << '§6Uptime: §c${format_uptime(ctx.uptime_seconds)}§r'
	lines << '§6Current TPS: ${tps_color}${ctx.tps:.2f} §7(§f${ctx.load:.1f}%§7)§r'
	lines << '§6Average TPS: ${tps_color}${ctx.tps:.2f} §7(§f${ctx.load:.1f}%§7)§r'
	lines << '§6Memory: §c${format_bytes(ctx.memory_used_bytes)}§6/§c${format_bytes(ctx.memory_heap_bytes)}§r'
	lines << '§6Chunk cache: §c${ctx.chunk_cache_entries}§6 entries (~§c${format_bytes(ctx.chunk_cache_bytes)}§6), generation workers: §c${ctx.active_chunk_generation_count}§r'
	lines << '§6Online players: §c${ctx.player_count}§6/§c${ctx.max_players}§r'
	lines << '§6World: §a${ctx.server_motd}§r'
	sender.send_message(lines.join('\n'))!
}

fn tps_format_color(tps f64) string {
	return match true {
		tps < 12.0 { '§c' }
		tps < 17.0 { '§6' }
		else { '§a' }
	}
}

fn format_bytes(total i64) string {
	if total < 1024 {
		return '${total} B'
	}
	mut value := f64(total)
	units := ['KiB', 'MiB', 'GiB', 'TiB']
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

fn format_uptime(total i64) string {
	seconds := total % 60
	minutes := (total / 60) % 60
	hours := (total / 3600) % 24
	days := total / 86400
	if days > 0 {
		return '${days} days ${hours} hours ${minutes} minutes ${seconds} seconds'
	}
	if hours > 0 {
		return '${hours} hours ${minutes} minutes ${seconds} seconds'
	}
	if minutes > 0 {
		return '${minutes} minutes ${seconds} seconds'
	}
	return '${seconds} seconds'
}
