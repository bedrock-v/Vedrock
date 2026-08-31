module session

import server.internal.gamedata
import server.world
import server.world.db
import time

// ActorIdentityTask reports whether the actor loop's own thread is recognised
// from inside a running task.
struct ActorIdentityTask {
	answer chan bool
}

fn (t ActorIdentityTask) name() string {
	return 'ActorIdentityTask'
}

fn (t ActorIdentityTask) run(mut tx WorldTx) {
	t.answer <- tx.wr.on_actor_thread()
}

// YieldingTask resubmits itself remaining times, the shape a task uses to
// process a large job in bounded batches without routing the remainder back
// through a queue that may be full.
struct YieldingTask {
	remaining int
	done      chan bool
}

fn (t YieldingTask) name() string {
	return 'YieldingTask'
}

fn (t YieldingTask) run(mut tx WorldTx) {
	if t.remaining <= 1 {
		t.done <- true
		return
	}
	tx.resubmit(YieldingTask{
		remaining: t.remaining - 1
		done:      t.done
	})
}

fn actor_identity_runtime(name string) &WorldRuntime {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world(name, none, 'void', world.overworld)
	hub.add_world(target)
	return hub.world_runtime(name) or { panic('expected world runtime') }
}

// test_on_actor_thread_is_true_only_on_the_actor asserts the identity
// WorldRuntime publishes is the actor's own, not merely non zero. Without it a
// blocking call made from the actor waits on work only that thread can run,
// which hangs the world and, because shutdown waits for the active task,
// blocks shutdown with it.
fn test_on_actor_thread_is_true_only_on_the_actor() {
	mut wr := actor_identity_runtime('identity')

	answer := chan bool{cap: 1}
	assert wr.submit(ActorIdentityTask{ answer: answer })

	select {
		inside := <-answer {
			assert inside == true
		}
		5 * time.second {
			panic('actor never ran the identity task')
		}
	}

	// The test thread is not the actor, so the same check must be false here
	// even though the actor is running and its id is published.
	assert wr.on_actor_thread() == false
}

// test_continuation_depth_is_published_cross_thread asserts the continuation
// backlog is observable from another thread. The list is deliberately
// unbounded, so depth is the only signal that a task is rescheduling itself
// faster than it retires.
fn test_continuation_depth_is_published_cross_thread() {
	mut wr := actor_identity_runtime('continuations')

	before := wr.metrics()
	assert before.continuation_depth == 0
	assert before.continuation_peak == 0

	done := chan bool{cap: 1}
	assert wr.submit(YieldingTask{
		remaining: 12
		done:      done
	})

	select {
		_ := <-done {}
		10 * time.second {
			panic('yielding task never finished')
		}
	}

	after := wr.metrics()
	// Every yield leaves exactly one continuation outstanding, so the peak is
	// reached repeatedly rather than accumulating.
	assert after.continuation_peak >= 1
	// The backlog is retired, not merely capped.
	assert after.continuation_depth == 0
}
