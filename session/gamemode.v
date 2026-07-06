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

fn (mut s NetworkSession) set_gamemode(mode int) {
	s.game_mode = mode
	s.transport.send(&protocol.SetPlayerGameTypePacket{
		gamemode: mode
	}) or {}
	s.transport.send(&protocol.UpdateAbilitiesPacket{
		data: s.build_abilities()
	}) or {}
}
