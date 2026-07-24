module session

import time
import server.internal.gamedata
import server.world
import server.world.db
import server.event

fn new_test_world_runtime() &WorldRuntime {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('test', none, 'flat', world.overworld)
	return new_world_runtime(hub, w)
}

// NoopTask does nothing, used purely as a synchronization/traffic filler.
struct NoopTask {}

fn (t NoopTask) run(mut tx WorldTx) {}

fn test_submit_runs_task_on_actor_thread() {
	mut wr := new_test_world_runtime()
	defer {
		wr.shutdown()
	}
	result := world_call[int](mut wr, fn (mut tx WorldTx) int {
		return 42
	}) or { panic('world_call was rejected while running') }
	assert result == 42
}

fn test_try_submit_runs_task() {
	mut wr := new_test_world_runtime()
	defer {
		wr.shutdown()
	}
	ok := wr.try_submit(NoopTask{})
	assert ok
}

fn test_submit_and_try_submit_reject_after_shutdown() {
	mut wr := new_test_world_runtime()
	wr.shutdown()
	assert wr.submit(NoopTask{}) == false
	assert wr.try_submit(NoopTask{}) == false
	// world_call must not hang forever once the world is stopped either.
	res := world_call[int](mut wr, fn (mut tx WorldTx) int {
		return 1
	})
	assert res == none
}

fn shutdown_race_submitter(mut wr WorldRuntime, times int) {
	for _ in 0 .. times {
		wr.submit(NoopTask{})
	}
}

fn shutdown_race_try_submitter(mut wr WorldRuntime, times int) {
	for _ in 0 .. times {
		wr.try_submit(NoopTask{})
	}
}

fn test_shutdown_is_race_free_under_concurrent_submitters() {
	mut wr := new_test_world_runtime()

	mut threads := []thread{}
	for _ in 0 .. 8 {
		threads << spawn shutdown_race_submitter(mut wr, 200)
	}
	for _ in 0 .. 8 {
		threads << spawn shutdown_race_try_submitter(mut wr, 200)
	}

	wr.shutdown() // must return cleanly even while submitters are still hammering it
	threads.wait()

	// Nothing should be able to land after shutdown() has returned.
	assert wr.submit(NoopTask{}) == false
	assert wr.try_submit(NoopTask{}) == false
}

fn test_shutdown_blocks_while_a_task_holds_the_actor() {
	mut wr := new_test_world_runtime()

	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	ok := wr.submit(BarrierTask{
		started: started
		release: release
	})
	assert ok
	_ := <-started // actor is now provably inside BarrierTask

	shutdown_done := chan bool{cap: 1}
	spawn fn [mut wr, shutdown_done] () {
		wr.shutdown()
		shutdown_done <- true
	}()

	// shutdown() must not have signalled completion yet. Give it a bounded
	// window to (incorrectly) finish, which it must not.
	select {
		_ := <-shutdown_done {
			assert false // shutdown() returned while the actor was still blocked
		}
		200 * time.millisecond {} // expected: still blocked, not a failure
	}

	release <- true // let BarrierTask finish, freeing the actor to actually stop

	select {
		_ := <-shutdown_done {} // expected: completes promptly now
		2000 * time.millisecond {
			assert false // shutdown() should have completed shortly after release
		}
	}
}

struct BarrierTask {
	started chan bool
	release chan bool
}

fn (t BarrierTask) run(mut tx WorldTx) {
	t.started <- true
	_ := <-t.release
}

fn wait_until(deadline_ms int, cond fn () bool) bool {
	deadline := time.now().add(deadline_ms * time.millisecond)
	for time.now() < deadline {
		if cond() {
			return true
		}
		time.sleep(2 * time.millisecond)
	}
	return cond()
}

fn test_tick_requests_coalesce_while_actor_is_busy() {
	mut wr := new_test_world_runtime()
	defer {
		wr.shutdown()
	}

	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	ok := wr.submit(BarrierTask{
		started: started
		release: release
	})
	assert ok
	_ := <-started // actor is now provably blocked inside BarrierTask, not yet touched tick_wakeup

	for i in 0 .. 50 {
		wr.request_tick(i64(1000 + i))
	}

	release <- true // let BarrierTask finish so the actor can drain tick_wakeup

	assert wait_until(2000, fn [wr] () bool {
		return wr.tick_runs_count() > 0
	})
	assert wr.tick_runs_count() == 1
	assert wr.tick_snapshot() == 1049
}

fn test_advance_tick_bounded_catchup_resyncs_clock() {
	mut wr := new_test_world_runtime()
	defer {
		wr.shutdown()
	}

	wr.request_tick(500)
	assert wait_until(2000, fn [wr] () bool {
		return wr.tick_snapshot() == 500
	})
	assert wr.simulated_steps_count() == max_world_catchup_ticks
}

struct EventCounter {
	event.NopHandler
mut:
	hits int
}

fn sync_barrier(mut wr WorldRuntime) {
	world_call[bool](mut wr, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected - world unexpectedly stopped') }
}

fn test_register_and_unregister_event_go_through_the_actor() {
	mut wr := new_test_world_runtime()
	defer {
		wr.shutdown()
	}

	handler := &EventCounter{}
	wr.register_event(handler, .normal)
	sync_barrier(mut wr)
	assert wr.events.len() == 1

	wr.unregister_event(handler)
	sync_barrier(mut wr)
	assert wr.events.len() == 0
}
