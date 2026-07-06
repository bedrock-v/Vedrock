// todo : change other people's gamemodes
module command

import protocol
import permission

pub struct GamemodeCommand {}

pub fn (c GamemodeCommand) name() string {
	return 'gamemode'
}

pub fn (c GamemodeCommand) description() string {
	return "Sets a player's game mode"
}

pub fn (c GamemodeCommand) aliases() []string {
	return ['gm']
}

pub fn (c GamemodeCommand) permission() string {
	return permission.command_gamemode_self
}

pub fn (c GamemodeCommand) arguments() []Argument {
	return [
		StringEnumArgument{
			arg_name: 'mode'
			values:   ['survival', 's', '0', 'creative', 'c', '1', 'adventure', 'a', '2', 'spectator',
				'sp', '6']
		},
	]
}

pub fn (c GamemodeCommand) execute(mut sender Sender, ctx Context) ! {
	mode := parse_gamemode(ctx.args[0]) or {
		sender.send_message(ctx.lang.t('command.gamemode.usage'))!
		return
	}
	sender.set_gamemode(mode)
	sender.send_translation('%commands.gamemode.success.self', [
		'%${gamemode_translation_key(mode)}',
	])!
}

fn parse_gamemode(arg string) ?int {
	return match arg.to_lower() {
		'survival', 's', '0' { protocol.game_type_survival }
		'creative', 'c', '1' { protocol.game_type_creative }
		'adventure', 'a', '2' { protocol.game_type_adventure }
		'spectator', 'sp', '6' { protocol.game_type_spectator }
		else { none }
	}
}

fn gamemode_translation_key(mode int) string {
	return match mode {
		protocol.game_type_survival { 'gameMode.survival' }
		protocol.game_type_adventure { 'gameMode.adventure' }
		protocol.game_type_spectator { 'gameMode.spectator' }
		else { 'gameMode.creative' }
	}
}
