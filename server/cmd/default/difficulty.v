module default

import protocol
import server.permission
import server.cmd

pub struct DifficultyCommand {}

pub fn (c DifficultyCommand) name() string {
	return 'difficulty'
}

pub fn (c DifficultyCommand) description() string {
	return "Sets the world's difficulty"
}

pub fn (c DifficultyCommand) aliases() []string {
	return []
}

pub fn (c DifficultyCommand) permission() string {
	return permission.command_difficulty
}

pub fn (c DifficultyCommand) arguments() []cmd.Argument {
	return [
		cmd.StringEnumArgument{
			arg_name: 'difficulty'
			values:   ['peaceful', 'p', '0', 'easy', 'e', '1', 'normal', 'n', '2', 'hard', 'h', '3']
		},
	]
}

fn parse_difficulty(arg string) ?int {
	return match arg.to_lower() {
		'peaceful', 'p', '0' { protocol.difficulty_peaceful }
		'easy', 'e', '1' { protocol.difficulty_easy }
		'normal', 'n', '2' { protocol.difficulty_normal }
		'hard', 'h', '3' { protocol.difficulty_hard }
		else { none }
	}
}

fn difficulty_name(value int) string {
	return match value {
		protocol.difficulty_peaceful { 'peaceful' }
		protocol.difficulty_normal { 'normal' }
		protocol.difficulty_hard { 'hard' }
		else { 'easy' }
	}
}

pub fn (c DifficultyCommand) execute(mut sender cmd.Sender, ctx cmd.Context) ! {
	value := parse_difficulty(ctx.args[0]) or {
		sender.send_message(ctx.lang.t('cmd.difficulty.usage'))!
		return
	}
	sender.set_difficulty(value)
	sender.send_message(ctx.lang.tf('cmd.difficulty.set', {
		'Difficulty': difficulty_name(value)
	}))!
}
