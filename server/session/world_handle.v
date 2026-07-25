module session

import server.world

// World is a public handle for a loaded world. Its methods route mutations
// through the owning world thread without exposing runtime or storage internals.
//
// Player and entity access will be added once safe reference types exist.
// World time is omitted because it is currently global, not owned per world.
pub struct World {
mut:
	runtime &WorldRuntime
}

// world_handle wraps the world loaded under name in a public World or
// returns none if no such world is loaded.
pub fn (mut h Hub) world_handle(name string) ?World {
	wr := h.world_runtime(name) or { return none }
	return World{
		runtime: wr
	}
}

pub fn (w World) name() string {
	return w.runtime.world.name
}

pub fn (w World) dimension() world.Dimension {
	return w.runtime.world.dimension
}

// current_tick is this world's own simulation clock, safe to read from any
// thread. It never requires a round trip through the actor, so it stays
// readable even while that actor is stuck, the same reason WorldMetrics
// exists.
pub fn (w World) current_tick() i64 {
	return w.runtime.tick_snapshot()
}

// block_at returns the stored block override at pos, falling back to the
// world's configured generator. Both sources are safe to read off thread,
// so no world actor call is needed.
pub fn (w World) block_at(x int, y int, z int) world.Block {
	if id := w.runtime.world.block_override(x, y, z) {
		return world.block_from_id(id)
	}
	gen := w.runtime.world.make_generator(w.runtime.hub.build_generator(w.runtime.world))
	return world.block_from_id(gen.block_at(x, y, z))
}

// set_block applies an authoritative block change through the owning world
// thread.
pub fn (mut w World) set_block(x int, y int, z int, b world.Block) ! {
	world_call[bool](mut w.runtime, fn [x, y, z, b] (mut tx WorldTx) bool {
		tx.set_block(x, y, z, b.network_id)
		return true
	}) or { return error('world "${w.runtime.world.name}" is shutting down') }
}
