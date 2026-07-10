module default

import server.permission
import server.cmd

pub struct OpCommand {}

pub fn (c OpCommand) name() string {
	return 'op'
}

pub fn (c OpCommand) description() string {
	return 'Grants operator status to a player'
}

pub fn (c OpCommand) aliases() []string {
	return []
}

pub fn (c OpCommand) permission() string {
	return permission.command_op
}

pub fn (c OpCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name: 'player'
		},
	]
}

pub fn (c OpCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	target_name := ctx.args[0]
	mut target := sender.find_player(target_name) or {
		sender.send_message(ctx.lang.tf('cmd.player_not_found', {
			'Name': target_name
		}))!
		return
	}
	target.set_operator(true)
	target.send_translation('%commands.op.message', [])!
	sender.send_translation('%commands.op.success', [target.name()])!
}

pub struct DeopCommand {}

pub fn (c DeopCommand) name() string {
	return 'deop'
}

pub fn (c DeopCommand) description() string {
	return 'Revokes operator status from a player'
}

pub fn (c DeopCommand) aliases() []string {
	return []
}

pub fn (c DeopCommand) permission() string {
	return permission.command_op
}

pub fn (c DeopCommand) arguments() []cmd.Argument {
	return [
		cmd.StringArgument{
			arg_name: 'player'
		},
	]
}

pub fn (c DeopCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	target_name := ctx.args[0]
	mut target := sender.find_player(target_name) or {
		sender.send_message(ctx.lang.tf('cmd.player_not_found', {
			'Name': target_name
		}))!
		return
	}
	target.set_operator(false)
	target.send_translation('%commands.deop.message', [])!
	sender.send_translation('%commands.deop.success', [target.name()])!
}
