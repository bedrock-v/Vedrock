module event

import server.player

// WorldLoadData is dispatched after a world is created or loaded and
// registered. The world already exists by the time this
// fires, cancelling has no effect.
pub struct WorldLoadData {
pub:
	name string
pub mut:
	player player.View
}

// WorldUnloadData is dispatched before a loaded world is unloaded. Cancelling
// it keeps the world loaded.
pub struct WorldUnloadData {
pub:
	name string
pub mut:
	player player.View
}
