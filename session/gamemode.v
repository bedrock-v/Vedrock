module session

import protocol

fn gamemode_id(name string) int {
	return match name.to_lower() {
		'survival' { protocol.game_type_survival }
		'adventure' { protocol.game_type_adventure }
		'spectator' { protocol.game_type_spectator }
		else { protocol.game_type_creative }
	}
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

fn (mut s NetworkSession) run_gamemode(args []string) ! {
	if args.len == 0 {
		s.send_translation('§c%commands.gamemode.usage', [])!
		return
	}
	mode := parse_gamemode(args[0]) or {
		s.send_translation('§c%commands.gamemode.usage', [])!
		return
	}
	s.set_gamemode(mode)
	s.send_translation('%commands.gamemode.success.self', [
		'%${gamemode_translation_key(mode)}',
	])!
}

fn (mut s NetworkSession) set_gamemode(mode int) {
	s.game_mode = mode
	s.transport.send(&protocol.SetPlayerGameTypePacket{
		gamemode: mode
	}) or {}
	s.transport.send(&protocol.UpdateAbilitiesPacket{
		data: s.build_abilities()
	}) or {}
}
