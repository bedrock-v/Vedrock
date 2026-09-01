module worldrt

import server.internal.gamedata
import server.world

// Services is the narrow slice of the surrounding server a world task needs
// while running on the actor: the block palette and item tables it looks
// placement rules up in, the server tick it stamps work with and the id
// allocator it takes runtime ids from.
//
// It is an interface rather than the server type itself so a world runtime
// never gains a way to reach sessions. Anything that does need a session
// carries one itself; see the tasks in the session package.
pub interface Services {
	block_palette() &world.BlockPalette
	game_data() &gamedata.GameData
mut:
	current_tick() i64
	allocate_runtime_id() u64
}
