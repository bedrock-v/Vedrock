module scheduler

// Task is the unit of scheduled work, modelled on PocketMine's Task. Implement
// run() with whatever should happen when the task fires. For one-off callbacks
// without a dedicated struct, use ClosureTask.
pub interface Task {
	run()
}

// ClosureTask adapts a plain function into a Task so callers can schedule a
// closure without declaring a struct.
pub struct ClosureTask {
	callback fn () @[required]
}

pub fn (t &ClosureTask) run() {
	t.callback()
}

// new_closure_task wraps cb in a Task.
pub fn new_closure_task(cb fn ()) &ClosureTask {
	return &ClosureTask{
		callback: cb
	}
}

// TaskHandler is the scheduler's live record of a queued task. It is returned
// from every schedule_* call so the caller can cancel the task later. Mirrors
// PocketMine's TaskHandler: delay and period are in ticks, next_run is the tick
// the task fires on.
@[heap]
pub struct TaskHandler {
	id     int
	delay  i64
	period i64
mut:
	task      Task
	next_run  i64
	cancelled bool
}

// id returns the scheduler-assigned handle id.
pub fn (h &TaskHandler) id() int {
	return h.id
}

// is_cancelled reports whether the task has been cancelled.
pub fn (h &TaskHandler) is_cancelled() bool {
	return h.cancelled
}

// cancel stops the task from running again. A repeating task will not fire
// after this; a pending delayed task never fires.
pub fn (mut h TaskHandler) cancel() {
	h.cancelled = true
}

// is_repeating reports whether the task reschedules itself after each run.
pub fn (h &TaskHandler) is_repeating() bool {
	return h.period > 0
}
