module scheduler

// CounterTask bumps a shared counter every time it runs.
struct CounterTask {
mut:
	runs &int
}

fn (t &CounterTask) run() {
	unsafe {
		(*t.runs)++
	}
}

fn test_delayed_runs_once_after_delay() {
	mut runs := 0
	mut s := new_scheduler()
	s.run_delayed(&CounterTask{ runs: &runs }, 5)

	// Not due before the delay elapses.
	s.heartbeat(1)
	s.heartbeat(4)
	assert runs == 0
	// Fires on the delay tick, then never again.
	s.heartbeat(5)
	assert runs == 1
	s.heartbeat(6)
	s.heartbeat(20)
	assert runs == 1
	assert s.count() == 0
}

fn test_repeating_runs_every_period() {
	mut runs := 0
	mut s := new_scheduler()
	s.run_repeating(&CounterTask{ runs: &runs }, 3)

	s.heartbeat(0) // starts next tick, next_run == 0 so fires now
	s.heartbeat(3)
	s.heartbeat(6)
	assert runs == 3
	assert s.count() == 1
}

fn test_cancel_stops_task() {
	mut runs := 0
	mut s := new_scheduler()
	handler := s.run_repeating(&CounterTask{ runs: &runs }, 2)

	s.heartbeat(0)
	assert runs == 1
	s.cancel(handler.id())
	s.heartbeat(2)
	s.heartbeat(4)
	assert runs == 1
	assert s.count() == 0
}

fn test_closure_task() {
	mut ran := 0
	p := &ran
	mut s := new_scheduler()
	s.run_task(new_closure_task(fn [p] () {
		unsafe {
			*p = 1
		}
	}))
	s.heartbeat(1)
	assert ran == 1
}

fn test_cancel_all_clears_queue() {
	mut runs := 0
	mut s := new_scheduler()
	s.run_repeating(&CounterTask{ runs: &runs }, 1)
	s.run_repeating(&CounterTask{ runs: &runs }, 1)
	assert s.count() == 2
	s.cancel_all()
	assert s.count() == 0
	s.heartbeat(5)
	assert runs == 0
}
