module session

import server.scheduler
import server.worldrt

// Both schedulers share one generic table, instantiated once at scheduler.Task
// and once at worldrt.WorldTask. A V codegen bug crosswires the two bodies when
// both instantiations live in one binary, storing a task of one interface type
// into the other's field. Nothing else in the tree links both modules and
// schedules on both, so this test is what proves the sharing is sound.

struct CountingTask {
mut:
	ran &int
}

fn (t CountingTask) run() {
	unsafe {
		(*t.ran)++
	}
}

struct CountingWorldTask {
mut:
	ran &int
}

fn (t CountingWorldTask) run(mut tx worldrt.WorldTx) {
	unsafe {
		(*t.ran)++
	}
}

fn (t CountingWorldTask) name() string {
	return 'counting-world'
}

fn test_both_scheduler_instantiations_keep_their_own_tasks() {
	mut global_runs := 0
	mut sched := scheduler.new_scheduler()
	global_handle := sched.run_task(CountingTask{ ran: &global_runs })

	mut world_runs := 0
	mut world_sched := worldrt.new_world_scheduler()
	world_handle := world_sched.add(CountingWorldTask{ ran: &world_runs }, 0, 0, 0)

	assert global_handle.id() == 1
	assert world_handle.id() == 1
	// Reading the task back dispatches through whichever interface was
	// actually stored: a crosswired store lands on the wrong vtable here.
	assert world_handle.work().name() == 'counting-world'

	sched.heartbeat(0)
	assert global_runs == 1
	assert world_runs == 0
}

// The crosswire is per generic method, every method the two schedulers share
// has to be instantiated at both interfaces for this to prove anything.
fn test_the_shared_surface_works_at_both_instantiations() {
	mut delayed_runs := 0
	mut repeating_runs := 0
	mut cancelled_runs := 0
	mut sched := scheduler.new_scheduler()

	sched.run_delayed(CountingTask{ ran: &delayed_runs }, 3)
	sched.run_repeating(CountingTask{ ran: &repeating_runs }, 2)
	doomed := sched.run_task(CountingTask{ ran: &cancelled_runs })
	assert sched.count() == 3

	sched.cancel(doomed.id())
	for tick in 0 .. 7 {
		sched.heartbeat(i64(tick))
	}
	assert cancelled_runs == 0
	assert delayed_runs == 1
	assert repeating_runs > 1

	sched.cancel_all()
	assert sched.count() == 0

	mut world_runs := 0
	mut world_sched := worldrt.new_world_scheduler()
	repeating := world_sched.add(CountingWorldTask{ ran: &world_runs }, 5, 2, 100)
	assert repeating.is_repeating()
	assert !repeating.is_cancelled()
	world_sched.cancel(repeating.id())
	assert repeating.is_cancelled()
	// The world task never ran: only its own scheduler's heartbeat runs it,
	// and that one is driven by a world actor holding a transaction.
	assert world_runs == 0
}
