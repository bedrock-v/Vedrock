module session

// WorldCallTask wraps a closure for execution on a WorldRuntime actor through
// the regular WorldTask queue.
struct WorldCallTask {
	label  string
	run_fn fn (mut tx WorldTx) = unsafe { nil }
}

// name reports the caller supplied label so WorldMetrics attributes a slow
// call to the operation that made it rather than to this wrapper type.
fn (t WorldCallTask) name() string {
	if t.label == '' {
		return 'WorldCallTask'
	}
	return t.label
}

fn (t WorldCallTask) run(mut tx WorldTx) {
	t.run_fn(mut tx)
}

// world_call runs "f" on this WorldRuntime's actor thread and blocks until its
// result is available. It returns none if the runtime rejects submission,
// such as during shutdown.
//
// label identifies the operation in WorldMetrics.longest_task_name.
//
// It panics when called from the runtime's own actor thread. That call can
// only wait for work the calling thread is itself responsible for running, so
// it would hang the world permanently and, because shutdown waits for the
// active task, block shutdown with it. Code already inside a task must use its
// WorldTx directly.
fn world_call[T](label string, mut wr WorldRuntime, f fn (mut tx WorldTx) T) ?T {
	if wr.on_actor_thread() {
		panic('world_call("${label}") from world "${wr.world.name}" actor thread would deadlock; use the WorldTx already in scope')
	}
	result := chan T{cap: 1}
	if !wr.submit(WorldCallTask{
		label:  label
		run_fn: fn [f, result] [T](mut tx WorldTx) {
			result <- f(mut tx)
		}
	}) {
		return none
	}
	return <-result
}
