module scheduler

// Task is scheduled work run synchronously on the server's global tick
// thread. Implement run() with the work to perform when the task fires.
//
// Tasks must remain short and non-blocking: a slow task delays the global
// tick cadence for every world. Schedule world specific work through that
// World's scheduler instead. For simple one off callbacks, use ClosureTask.
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

// TaskHandler is the live record of a queued global task. See Handler.
pub type TaskHandler = Handler[Task]
