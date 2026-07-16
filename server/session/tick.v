module session

import protocol
import protocol.types
import server.world.db

// TickJob contains the per tick server state passed from tick_loop to Hub.
// Each snapshot includes the current world time, tps and tick load.
//
// tick_loop owns the 20 Hz tick cadence and calculates the tps and load
// metrics on its own thread. It submits one TickJob per tick instead of
// modifying Hub's fields directly.
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
	h.tick_worlds()
}

// tick_worlds advances each loaded world by one game tick, processing random
// ticks and any scheduled ticks that are due. It then broadcasts the block
// changes produced by those ticks.
//
// This runs on run_jobs()'s single thread alongside all other cross-session state mutations.
fn (mut h Hub) tick_worlds() {
	h.mutex.lock()
	mut worlds := []&db.World{cap: h.worlds.len}
	for _, w in h.worlds {
		worlds << w
	}
	h.mutex.unlock()

	for mut w in worlds {
		for change in w.tick(&h.blocks) {
			h.broadcast(&protocol.UpdateBlockPacket{
				block_position:   types.BlockPosition{change.x, change.y, change.z}
				block_runtime_id: change.id
				flags:            block_update_flags
				data_layer_id:    0
			})
		}
	}
}
