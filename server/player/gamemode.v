module player

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
