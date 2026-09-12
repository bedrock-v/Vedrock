module scheduler

// Scheduler runs Tasks against the server tick clock. Tasks may be scheduled
// from session threads while heartbeat() runs on the tick thread. A mutex guards
// the task table; tasks themselves run outside the lock so a task may safely
// schedule more work.
//
// See Task's own doc comment for exactly where and how run() executes.
// synchronously on the single global tick thread, not a per-world or
// per-task thread.
@[heap]
pub struct Scheduler {
mut:
	table Table[Task]
}

pub fn new_scheduler() &Scheduler {
	return &Scheduler{
		table: new_table[Task]()
	}
}

// run_task queues task to run on the next tick.
pub fn (mut s Scheduler) run_task(task Task) &TaskHandler {
	return s.table.add_now(task, 0, 0)
}

// run_delayed queues task to run once, delay ticks from now.
pub fn (mut s Scheduler) run_delayed(task Task, delay i64) &TaskHandler {
	return s.table.add_now(task, delay, 0)
}

// run_repeating queues task to run every period ticks, starting next tick.
pub fn (mut s Scheduler) run_repeating(task Task, period i64) &TaskHandler {
	return s.table.add_now(task, 0, period)
}

// run_delayed_repeating queues task to first run after delay ticks, then every
// period ticks.
pub fn (mut s Scheduler) run_delayed_repeating(task Task, delay i64, period i64) &TaskHandler {
	return s.table.add_now(task, delay, period)
}

// cancel stops and removes the task with the given id, if present.
pub fn (mut s Scheduler) cancel(id int) {
	s.table.cancel(id)
}

// cancel_all cancels and drops every queued task.
pub fn (mut s Scheduler) cancel_all() {
	s.table.cancel_all()
}

// count reports how many tasks are queued.
pub fn (mut s Scheduler) count() int {
	return s.table.count()
}

// heartbeat advances the clock to tick and runs every task due at or before
// it. Called once per server tick from the tick actor thread.
pub fn (mut s Scheduler) heartbeat(tick i64) {
	mut due := s.table.due(tick)
	for handler in due {
		if handler.is_cancelled() {
			continue
		}
		mut task := handler.work()
		task.run()
	}
	s.table.settle(mut due, tick)
}
