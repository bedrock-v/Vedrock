module player

import bedrock_v.protocol.current as proto

// Gamemode is a player's game mode. Player and View expose this directly.
pub enum Gamemode {
	survival
	creative
	adventure
	spectator
}

// allows_taking_damage reports whether a player in this mode can be hurt.
pub fn (g Gamemode) allows_taking_damage() bool {
	return g == .survival || g == .adventure
}

// allows_flying reports whether a player in this mode can fly freely.
pub fn (g Gamemode) allows_flying() bool {
	return g == .creative || g == .spectator
}

// gamemode_from_wire maps Bedrock's game type values onto Gamemode. The
// spectator variants all collapse: the server keeps one spectator mode.
pub fn gamemode_from_wire(v int) Gamemode {
	return match v {
		proto.game_type_creative {
			.creative
		}
		proto.game_type_adventure {
			.adventure
		}
		proto.game_type_spectator, proto.game_type_survival_spectator,
		proto.game_type_creative_spectator {
			.spectator
		}
		else {
			.survival
		}
	}
}

// gamemode_to_wire is the inverse of gamemode_from_wire.
pub fn gamemode_to_wire(g Gamemode) int {
	return match g {
		.survival { proto.game_type_survival }
		.creative { proto.game_type_creative }
		.adventure { proto.game_type_adventure }
		.spectator { proto.game_type_spectator }
	}
}

// gamemode_from_name reads a configured or typed mode name. Anything
// unrecognised is creative, which is what the config default expects.
pub fn gamemode_from_name(name string) Gamemode {
	return match name.to_lower() {
		'survival' { .survival }
		'adventure' { .adventure }
		'spectator' { .spectator }
		else { .creative }
	}
}

// collects_experience reports whether this mode picks experience up at all.
// Spectators pass through the world without touching it; every other mode
// collects, since experience is not damage and does not follow its rules.
pub fn (g Gamemode) collects_experience() bool {
	return g != .spectator
}
