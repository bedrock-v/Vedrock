module command

import protocol

pub struct VersionCommand {}

pub fn (c VersionCommand) name() string {
	return 'version'
}

pub fn (c VersionCommand) description() string {
	return 'Show the server software and protocol version'
}

pub fn (c VersionCommand) aliases() []string {
	return ['ver', 'about']
}

pub fn (c VersionCommand) execute(ctx Context) string {
	return '§aVedrock §7for Minecraft Bedrock §f${protocol.minecraft_version_network} §7(protocol §f${protocol.current_protocol}§7)'
}

pub struct StatusCommand {}

pub fn (c StatusCommand) name() string {
	return 'status'
}

pub fn (c StatusCommand) description() string {
	return 'Show the current server status'
}

pub fn (c StatusCommand) aliases() []string {
	return ['stats']
}

pub fn (c StatusCommand) execute(ctx Context) string {
	return '§6${ctx.server_motd}\n§7Players: §f${ctx.player_count}§7/§f${ctx.max_players}'
}
