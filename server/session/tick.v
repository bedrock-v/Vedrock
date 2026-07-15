module session

// TickJob carries the once-a-tick snapshot server/server.v's tick_loop
// computes (world time, tps, load, etc.) into Hub.
// tick_loop owns the 20 Hz sleep/wake cadence and the tps/load window math on its own thread
// and submits one of these per tick rather than writing Hub's fields directly.
pub struct TickJob {
pub:
	tick       i64
	world_time int
	tps        f64
	load       f64
}

fn (j TickJob) run(mut h Hub) {
	h.current_tick = j.tick
	h.world_time = j.world_time
	h.set_tps(j.tps)
	h.set_load(j.load)
	h.tick_effects()
	h.scheduler.heartbeat(j.tick)
	h.entities.tick()
	h.liquids.tick()
}
