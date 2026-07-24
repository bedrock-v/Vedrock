module default

import server.permission
import server.cmd

pub struct KillCommand {}

pub fn (c KillCommand) name() string {
	return 'kill'
}

pub fn (c KillCommand) description() string {
	return 'Kills yourself or another player'
}

pub fn (c KillCommand) aliases() []string {
	return []
}

pub fn (c KillCommand) permission() string {
	return permission.command_kill_self
}

pub fn (c KillCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name:     'player'
			arg_optional: true
		},
	]
}

pub fn (c KillCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	if ctx.args.len == 0 {
		if !sender.is_player() {
			sender.send_message(ctx.lang.t('cmd.player_only'))!
			return
		}
		sender.kill()
		sender.send_message(ctx.lang.t('cmd.kill_self'))!
		return
	}
	if !sender.has_permission(permission.command_kill_other) {
		sender.send_message(ctx.lang.t('cmd.no_permission'))!
		return
	}
	target_name := ctx.args[0]
	mut target := sender.find_player(target_name) or {
		sender.send_message(ctx.lang.tf('cmd.player_not_found', {
			'Name': target_name
		}))!
		return
	}
	target.kill()
	sender.send_message(ctx.lang.tf('cmd.kill_other', {
		'Name': target.name()
	}))!
}
