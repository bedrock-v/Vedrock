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

// spawn_y returns the configured generator's spawn height for this world.
// The generator can be resolved from thread safe world and registry state,
// so no world actor call is required.
pub fn (w World) spawn_y() int {
	gen := w.runtime.world.make_generator(w.runtime.hub.build_generator(w.runtime.world))
	return gen.spawn_y()
}

// set_block applies an authoritative block change through the owning world
// thread.
pub fn (mut w World) set_block(x int, y int, z int, b world.Block) ! {
	world_call[bool](mut w.runtime, fn [x, y, z, b] (mut tx WorldTx) bool {
		tx.set_block(x, y, z, b.network_id)
		return true
	}) or { return error('world "${w.runtime.world.name}" is shutting down') }
}

// players returns a PlayerRef for every player currently registered in this
// world. The lookup runs through the world's actor owned player registry.
//
// If the world is shutting down, players returns an empty slice.
pub fn (mut w World) players() []PlayerRef {
	return world_call[[]PlayerRef](mut w.runtime, fn (mut tx WorldTx) []PlayerRef {
		mut out := []PlayerRef{}
		for mut a in tx.wr.entities.player_actors() {
			if mut a is NetworkSession {
				out << player_ref_for(a)
			}
		}
		return out
	}) or { []PlayerRef{} }
}

// player_count returns the current number of players in this world.
// It is a thread safe snapshot and does not require a world actor round trip.
pub fn (w World) player_count() i64 {
	return w.runtime.player_count()
}

// entities returns an EntityRef for every non-player entity currently
// registered in this world. If the world is shutting down, it returns an
// empty slice.
pub fn (mut w World) entities() []EntityRef {
	return world_call[[]EntityRef](mut w.runtime, fn (mut tx WorldTx) []EntityRef {
		mut out := []EntityRef{}
		for e in tx.wr.entities.snapshot() {
			out << EntityRef{
				runtime_id: e.runtime_id()
				world_:     World{
					runtime: tx.wr
				}
			}
		}
		return out
	}) or { []EntityRef{} }
}

// metrics returns a snapshot of this world's runtime metrics including
// queue pressure, tick timing, persistence backlog and chunk generation
// load. It is thread safe and does not block on the world actor.
pub fn (mut w World) metrics() WorldMetrics {
	return w.runtime.metrics()
}

// run_task schedules f to run on this world's actor thread on its next
// simulated step.
//
// The callback must remain short and non blocking. A slow callback stalls
// only this world. Scheduled callbacks are fire and forget.
pub fn (mut w World) run_task(f fn (mut tx WorldTransaction)) &WorldTaskHandler {
	return w.runtime.task_scheduler.add(WorldClosureTask{
		callback: f
	}, 0, 0, w.runtime.tick_snapshot())
}

// run_delayed queues "f" to run once, delay simulated ticks of this world
// from now.
pub fn (mut w World) run_delayed(f fn (mut tx WorldTransaction), delay i64) &WorldTaskHandler {
	return w.runtime.task_scheduler.add(WorldClosureTask{
		callback: f
	}, delay, 0, w.runtime.tick_snapshot())
}

// run_repeating queues "f" to run every period simulated ticks of this
// world starting on the next step.
pub fn (mut w World) run_repeating(f fn (mut tx WorldTransaction), period i64) &WorldTaskHandler {
	return w.runtime.task_scheduler.add(WorldClosureTask{
		callback: f
	}, 0, period, w.runtime.tick_snapshot())
}

// cancel_task stops a previously scheduled world task from running again.
pub fn (mut w World) cancel_task(id int) {
	w.runtime.task_scheduler.cancel(id)
}
