module session

import time
import server.arena
import server.internal.gamedata
import server.world
import server.world.db

struct SoakBlockSource {}

fn (mut s SoakBlockSource) get_block(x int, y int, z int) int {
	return x + 1
}

struct SoakSlowTask {
	delay_ms int
}

fn (t SoakSlowTask) name() string {
	return 'SoakSlowTask'
}

fn (t SoakSlowTask) run(mut tx WorldTx) {
	time.sleep(t.delay_ms * time.millisecond)
}

fn soak_wait_until(deadline_ms int, cond fn () bool) bool {
	deadline := time.now().add(deadline_ms * time.millisecond)
	for time.now() < deadline {
		if cond() {
			return true
		}
		time.sleep(2 * time.millisecond)
	}
	return cond()
}

fn test_heavy_world_does_not_stall_quiet_world() {
	mut hub := new_hub(gamedata.GameData{})
	heavy := db.new_world('soak-heavy', none, 'void', world.overworld)
	hub.add_world(heavy)
	hub.set_default_world('soak-heavy')
	quiet := db.new_world('soak-quiet', none, 'void', world.overworld)
	hub.add_world(quiet)
	defer {
		hub.close_worlds()
	}

	mut wr_heavy := hub.world_runtime('soak-heavy') or { panic('expected soak-heavy runtime') }
	mut wr_quiet := hub.world_runtime('soak-quiet') or { panic('expected soak-quiet runtime') }

	blocks_needed := arena_restore_batch_size * 6 + 1
	mut src := SoakBlockSource{}
	snap := arena.capture(mut src, arena.new_box(0, 64, 0, blocks_needed - 1, 64, 0))!
	hub.restore_area(snap)

	stop := chan bool{cap: 1}
	slow_task_done := chan bool{cap: 1}
	spawn fn [mut wr_heavy, stop, slow_task_done] () {
		for {
			select {
				_ := <-stop {
					slow_task_done <- true
					return
				}
				else {}
			}
			wr_heavy.submit(SoakSlowTask{
				delay_ms: 15
			})
			time.sleep(5 * time.millisecond)
		}
	}()

	deadline := time.now().add(2000 * time.millisecond)
	mut last_quiet_tick := wr_quiet.tick_snapshot()
	mut samples := 0
	mut n := i64(1)
	for time.now() < deadline {
		hub.request_tick_all(n)
		n++
		// The quiet world must keep advancing every single sampled round
		// throughout the entire run.
		assert soak_wait_until(500, fn [wr_quiet, last_quiet_tick] () bool {
			return wr_quiet.tick_snapshot() > last_quiet_tick
		})
		last_quiet_tick = wr_quiet.tick_snapshot()

		// metrics() must stay queryable on both worlds throughout, regardless
		// of how loaded soak-heavy currently is.
		heavy_metrics := wr_heavy.metrics()
		assert heavy_metrics.world_name == 'soak-heavy'
		assert heavy_metrics.queued_tasks >= 0
		quiet_metrics := wr_quiet.metrics()
		assert quiet_metrics.world_name == 'soak-quiet'

		samples++
		time.sleep(20 * time.millisecond)
	}
	assert samples > 10 // proves this ran sustained across many rounds

	stop <- true
	_ := <-slow_task_done

	// The heavy world's arena restore still completes correctly despite
	// running underneath continuous competing load for the entire soak.
	assert soak_wait_until(10000, fn [wr_heavy, blocks_needed] () bool {
		id := wr_heavy.world.block_override(blocks_needed - 1, 64, 0) or { return false }
		return id == blocks_needed
	})
}
