module command

import protocol
import buildinfo
import permission

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

pub fn (c VersionCommand) permission() string {
	return permission.command_version
}

pub fn (c VersionCommand) execute(mut sender Sender, ctx Context) ! {
	sender.send_message(ctx.lang.tf('command.version.body', {
		'Software':  buildinfo.name
		'Version':   buildinfo.version
		'Hash':      buildinfo.git_hash
		'MCVersion': protocol.minecraft_version_network
		'Protocol':  protocol.current_protocol.str()
	}))!
}
