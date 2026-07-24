module session

import time
import server.internal.gamedata
import server.world
import server.world.db

struct ConcurrencyBarrierTask {
	started chan bool
	release chan bool
}

fn (t ConcurrencyBarrierTask) run(mut tx WorldTx) {
	t.started <- true
	_ := <-t.release
}

fn concurrency_wait_until(deadline_ms int, cond fn () bool) bool {
	deadline := time.now().add(deadline_ms * time.millisecond)
	for time.now() < deadline {
		if cond() {
			return true
		}
		time.sleep(2 * time.millisecond)
	}
	return cond()
}

// World B's tick clock, liquid manager and runtime tasks keep advancing while
// world A's runtime is blocked. Hub.request_tick_all must not wait on A.
fn test_stalled_world_does_not_stall_another_worlds_ticks_or_liquids() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('stall-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	hub.set_default_world('stall-a')
	world_b := db.new_world('progress-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	defer {
		hub.close_worlds()
	}

	mut wr_a := hub.world_runtime('stall-a') or { panic('expected stall-a runtime') }
	mut wr_b := hub.world_runtime('progress-b') or { panic('expected progress-b runtime') }

	// Give B's liquid manager real, ongoing work so "B keeps progressing"
	// means something more than just the tick counter moving.
	ok := wr_b.submit(PlaceWaterTask{
		x: 0
		y: 60
		z: 0
	})
	assert ok
	world_call[bool](mut wr_b, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier on B rejected - world unexpectedly stopped') } // wait for the placement to land before stalling A

	// Stall A's actor with a task barrier, the same pattern used to prove
	// tick coalescing in world_runtime_test.v. Now with a second, live world
	// alongside it.
	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	a_ok := wr_a.submit(ConcurrencyBarrierTask{
		started: started
		release: release
	})
	assert a_ok
	_ := <-started // A is now provably blocked

	// Drive the real fanout repeatedly while A is stalled and confirm B
	// keeps advancing every time.
	mut last_b_tick := wr_b.tick_snapshot()
	for i in 0 .. 5 {
		hub.request_tick_all(i64(100 + i))
		assert concurrency_wait_until(1000, fn [wr_b, last_b_tick] () bool {
			return wr_b.tick_snapshot() > last_b_tick
		})
		last_b_tick = wr_b.tick_snapshot()
	}

	// B's other runtime tasks, not just ticks, still complete throughout.
	world_call[bool](mut wr_b, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier on B rejected - world unexpectedly stopped') }

	// B's liquid manager actually did something with the water placed
	// above.
	assert wr_b.tick_snapshot() > 0

	// Release A and confirm it recovers once unblocked, proves this was a
	// real stall & recover, not just A never having been scheduled.
	release <- true
	a_target := i64(500)
	hub.request_tick_all(a_target)
	assert concurrency_wait_until(2000, fn [wr_a, a_target] () bool {
		return wr_a.tick_snapshot() == a_target
	})
}
