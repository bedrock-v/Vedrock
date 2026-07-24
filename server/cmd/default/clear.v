module default

import server.permission
import server.cmd

pub struct ClearCommand {}

pub fn (c ClearCommand) name() string {
	return 'clear'
}

pub fn (c ClearCommand) description() string {
	return "Clears yours or another player's inventory"
}

pub fn (c ClearCommand) aliases() []string {
	return []
}

pub fn (c ClearCommand) permission() string {
	return permission.command_clear_self
}

pub fn (c ClearCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name:     'player'
			arg_optional: true
		},
	]
}

pub fn (c ClearCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	if ctx.args.len == 0 {
		if !sender.is_player() {
			sender.send_message(ctx.lang.t('cmd.player_only'))!
			return
		}
		sender.clear_inventory()
		sender.send_message(ctx.lang.t('cmd.clear_self'))!
		return
	}
	if !sender.has_permission(permission.command_clear_other) {
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
	target.clear_inventory()
	sender.send_message(ctx.lang.tf('cmd.clear_other', {
		'Name': target.name()
	}))!
}
