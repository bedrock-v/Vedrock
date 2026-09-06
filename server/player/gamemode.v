module player

// Gamemode is a player's game mode. The mapping onto Bedrock's wire values
// lives in the session which is the layer that knows the wire.
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
