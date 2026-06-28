module command

import protocol

pub const software_name = 'Vedrock'
pub const software_version = '1.0.0-dev'
pub const software_git_hash = 'unknown'

pub struct VersionCommand {}

pub fn (c VersionCommand) name() string {
	return 'version'
}

pub fn (c VersionCommand) description() string {
	return 'Gets the version of this server including any plugins in use'
}

pub fn (c VersionCommand) aliases() []string {
	return ['ver', 'about']
}

pub fn (c VersionCommand) execute(ctx Context) string {
	mut lines := []string{}
	lines << 'This server is running §a${software_name}§r'
	lines << 'Server version: §a${software_version}§r (git hash: §a${software_git_hash}§r)'
	lines << 'Compatible Minecraft version: §a${protocol.minecraft_version_network}§r (protocol version: §a${protocol.current_protocol}§r)'
	return lines.join('\n')
}

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

pub fn (c StatusCommand) execute(ctx Context) string {
	mut lines := []string{}
	lines << '§a---- §rServer status§a ----§r'
	lines << 'Uptime: §c${format_uptime(ctx.uptime_seconds)}§r'
	lines << 'Current TPS: §a${ctx.tps:.2f}§r'
	lines << 'Online players: §c${ctx.player_count}§r/§c${ctx.max_players}§r'
	lines << 'World: §a${ctx.server_motd}§r'
	return lines.join('\n')
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
