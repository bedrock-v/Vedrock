module player

import server.event

// WorldLoadData is dispatched after a world is created or loaded and
// registered. The world already exists by the time this fires, cancelling has
// no effect. sender is whoever asked for the world, which is not necessarily a
// player: the console can load a world too.
pub struct WorldLoadData {
pub:
	name string
pub mut:
	sender event.CommandSource
}

// WorldUnloadData is dispatched before a loaded world is unloaded. Cancelling
// it keeps the world loaded. sender is as in WorldLoadData.
pub struct WorldUnloadData {
pub:
	name string
pub mut:
	sender event.CommandSource
}
