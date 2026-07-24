module session

// WorldCallTask wraps a closure for execution on a WorldRuntime actor through
// the regular WorldTask queue.
struct WorldCallTask {
	run_fn fn (mut tx WorldTx) = unsafe { nil }
}

fn (t WorldCallTask) run(mut tx WorldTx) {
	t.run_fn(mut tx)
}

// world_call runs "f" on this WorldRuntime's actor thread and blocks until its
// result is available. It returns none if the runtime rejects submission,
// such as during shutdown.
//
// It must not be called from the same WorldRuntime actor thread or it will
// deadlock waiting for that thread to execute the submitted task.
fn world_call[T](mut wr WorldRuntime, f fn (mut tx WorldTx) T) ?T {
	result := chan T{cap: 1}
	if !wr.submit(WorldCallTask{
		run_fn: fn [f, result] [T](mut tx WorldTx) {
			result <- f(mut tx)
		}
	}) {
		return none
	}
	return <-result
}
