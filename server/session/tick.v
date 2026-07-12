module session

// TickJob carries the once-a-tick snapshot server/server.v's tick_loop
// computes (world time, tps, load, etc.) into Hub.
// tick_loop owns the 20 Hz sleep/wake cadence and the tps/load window math on its own thread
// and submits one of these per tick rather than writing Hub's fields directly.
pub struct TickJob {
pub:
	world_time int
	tps        f64
	load       f64
}

fn (j TickJob) run(mut h Hub) {
	h.world_time = j.world_time
	h.set_tps(j.tps)
	h.set_load(j.load)
	h.tick_effects()
}
