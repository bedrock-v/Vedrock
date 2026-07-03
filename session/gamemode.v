module session

import protocol

fn gamemode_id(name string) int {
	return match name.to_lower() {
		'survival' { 0 }
		'adventure' { 2 }
		'spectator' { 6 }
		else { 1 }
	}
}

fn parse_gamemode(arg string) ?int {
	return match arg.to_lower() {
		'survival', 's', '0' { 0 }
		'creative', 'c', '1' { 1 }
		'adventure', 'a', '2' { 2 }
		'spectator', 'sp', '6' { 6 }
		else { none }
	}
}

fn gamemode_translation_key(mode int) string {
	return match mode {
		0 { 'gameMode.survival' }
		2 { 'gameMode.adventure' }
		6 { 'gameMode.spectator' }
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
	s.send_translation('%commands.gamemode.success.self', ['%${gamemode_translation_key(mode)}'])!
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
