module default

import server.permission
import server.cmd

pub struct MsgCommand {}

pub fn (c MsgCommand) name() string {
	return 'msg'
}

pub fn (c MsgCommand) description() string {
	return 'Send a private message to a player'
}

pub fn (c MsgCommand) aliases() []string {
	return ['tell', 'whisper', 'w']
}

pub fn (c MsgCommand) permission() string {
	return permission.command_msg
}

pub fn (c MsgCommand) arguments() []cmd.Argument {
	return [
		cmd.TextArgument{
			arg_name: 'player'
		},
		cmd.TextArgument{
			arg_name: 'message'
		},
	]
}

pub fn (c MsgCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	if ctx.args.len < 2 {
		sender.send_message(ctx.lang.t('cmd.msg.usage'))!
		return
	}

	target_name := ctx.args[0]
	message := ctx.args[1..].join(' ')

	mut target := sender.find_player(target_name) or {
		sender.send_message(ctx.lang.tf('cmd.msg.not_found', {'Name': target_name}))!
		return
	}

	target.send_message('[${ctx.sender_name} -> you] ${message}')!
	sender.send_message('[you -> ${target_name}] ${message}')!
}
