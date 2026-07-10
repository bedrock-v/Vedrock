module default

import server.permission
import server.cmd

pub struct SayCommand {}

pub fn (c SayCommand) name() string {
	return 'say'
}

pub fn (c SayCommand) description() string {
	return 'Broadcasts a message to every player as the server'
}

pub fn (c SayCommand) aliases() []string {
	return []
}

pub fn (c SayCommand) permission() string {
	return permission.command_say
}

pub fn (c SayCommand) arguments() []cmd.Argument {
	return [
		cmd.TextArgument{
			arg_name: 'message'
		},
	]
}

pub fn (c SayCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	if ctx.args.len == 0 {
		sender.send_message(ctx.lang.t('cmd.say.usage'))!
		return
	}
	sender.broadcast_message(ctx.args.join(' '))
}
