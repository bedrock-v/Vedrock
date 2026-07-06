module default

import protocol
import permission
import command

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

pub fn (c GamemodeCommand) arguments() []command.Argument {
	return [
		command.StringEnumArgument{
			arg_name: 'mode'
			values:   ['survival', 's', '0', 'creative', 'c', '1', 'adventure', 'a', '2', 'spectator',
				'sp', '6']
		},
		command.StringArgument{
			arg_name:     'player'
			arg_optional: true
		},
	]
}

pub fn (c GamemodeCommand) execute(mut sender command.Sender, ctx command.Context) ! {
	mode := parse_gamemode(ctx.args[0]) or {
		sender.send_message(ctx.lang.t('command.gamemode.usage'))!
		return
	}
	if ctx.args.len < 2 {
		sender.set_gamemode(mode)
		sender.send_translation('%commands.gamemode.success.self', [
			'%${gamemode_translation_key(mode)}',
		])!
		return
	}
	if !sender.has_permission(permission.command_gamemode_other) {
		sender.send_message(ctx.lang.t('command.no_permission'))!
		return
	}
	target_name := ctx.args[1]
	mut target := sender.find_player(target_name) or {
		sender.send_message(ctx.lang.tf('command.player_not_found', {
			'Name': target_name
		}))!
		return
	}
	target.set_gamemode(mode)
	target.send_translation('%gameMode.changed', [
		'%${gamemode_translation_key(mode)}',
	])!
	sender.send_translation('%commands.gamemode.success.other', [
		'%${gamemode_translation_key(mode)}',
		target.name(),
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
