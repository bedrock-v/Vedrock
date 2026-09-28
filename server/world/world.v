module world

import sync
import sync.stdatomic

// queue_cap is how many tasks may wait for the actor before a caller has to
// wait too. A queue that grows without limit turns a world that can't keep up
// into a process that runs out of memory. Producers block instead.
const queue_cap = 256

// Tx is access to one world's state and the only way anything reaches it. It
// is built on the actor's thread and lasts for one task.
//
// Nothing may keep a Tx past the callback it was handed to. Keep a Handle or a
// Ref, which are made to outlive a transaction.
pub struct Tx {
mut:
	world &Runtime
	// finished marks the transaction spent once its task is over.
	finished bool
	deferred []fn (mut tx Tx)
}

// Runtime owns one world. It runs a single thread and that thread is the only
// one that touches the world's state.
pub struct Runtime {
mut:
	name_    string
	tasks    chan Task
	entities map[u64]&Handle
	// current_tick counts the ticks this world has run. Only the actor
	// touches it.
	current_tick i64
	// actor holds the thread id of the actor once it is running.
	actor  &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	closed &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	// queueing is held while a caller checks closed and puts work on the queue
	// and taken for writing by close. Pushing to a closed channel is fatal in
	// V, so the check and the push can't be two separate steps.
	queueing &sync.RwMutex = sync.new_rwmutex()
	done     chan bool
}

// Task is one unit of work for a world's actor.
struct Task {
	name string
	run  fn (mut tx Tx) = unsafe { nil }
}

// start brings up a world, its actor thread and its tick loop.
pub fn start(name string) &Runtime {
	mut wr := start_manual(name)
	spawn wr.tick_loop()
	return wr
}

// start_manual brings up a world that does not tick on its own. It ticks when
// advance_tick is called, which is what a caller wants when the number of ticks
// has to be exactly the number it asked for.
pub fn start_manual(name string) &Runtime {
	mut wr := &Runtime{
		name_:    name
		tasks:    chan Task{cap: queue_cap}
		entities: map[u64]&Handle{}
		done:     chan bool{cap: 1}
	}
	spawn wr.run()
	return wr
}

// name is the world's name, for metrics and messages.
pub fn (wr &Runtime) name() string {
	return wr.name_
}

fn (mut wr Runtime) run() {
	wr.actor.store(sync.thread_id())
	for {
		task := <-wr.tasks or { break }
		mut tx := Tx{
			world:    wr
			deferred: []fn (mut tx Tx){}
		}
		task.run(mut tx)
		// Deferred work belongs to the task that queued it: it runs before the
		// task is done, in the order it was queued and may queue more.
		for i := 0; i < tx.deferred.len; i++ {
			f := tx.deferred[i]
			f(mut tx)
		}
		tx.finished = true
	}
	wr.done <- true
}

// on_actor_thread reports whether the caller is the actor itself.
pub fn (wr &Runtime) on_actor_thread() bool {
	id := wr.actor.load()
	return id != 0 && sync.thread_id() == id
}

// submit hands work to the actor and returns once the actor has taken it.
// It blocks while the queue is full, which is how a world that can't keep
// up slows down what feeds it.
//
// It fails once the world is closed.
pub fn (mut wr Runtime) submit(name string, f fn (mut tx Tx)) ! {
	wr.refuse_nested(name)
	wr.queueing.rlock()
	defer {
		wr.queueing.runlock()
	}
	if wr.closed.load() != 0 {
		return error('world "${wr.name_}" is closed')
	}
	wr.tasks <- Task{
		name: name
		run:  f
	}
}

// Outcome carries a result back from the actor.
struct Outcome[T] {
	value T
	err   ?IError
}

// call runs work on the actor and waits for its result.
//
// It fails once the world is closed.
pub fn call[T](mut wr Runtime, name string, f fn (mut tx Tx) !T) !T {
	wr.refuse_nested(name)
	result := chan Outcome[T]{cap: 1}
	wr.queueing.rlock()
	if wr.closed.load() != 0 {
		wr.queueing.runlock()
		return error('world "${wr.name_}" is closed')
	}
	wr.tasks <- Task{
		name: name
		run:  fn [f, result] [T](mut tx Tx) {
			value := f(mut tx) or {
				result <- Outcome[T]{
					err: err
				}
				return
			}
			result <- Outcome[T]{
				value: value
			}
		}
	}
	wr.queueing.runlock()
	outcome := <-result
	if e := outcome.err {
		return e
	}
	return outcome.value
}

// call_ref runs work against one entity, on whichever world holds it when the
// work runs. It fails when the entity is held by no world, when that world is
// closed or when it is no longer there by the time the work runs.
pub fn call_ref[T, R](r Ref[T], name string, f fn (mut tx Tx, e &T) !R) !R {
	mut wr := r.handle.world
	if isnil(wr) {
		return error('entity ${r.id()} is in no world')
	}
	return call[R](mut wr, name, fn [r, f] [T, R](mut tx Tx) !R {
		e := r.get(&tx) or {
			return error('entity ${r.id()} is no longer in world "${tx.world_name()}"')
		}
		return f(mut tx, e)
	})
}

// refuse_nested stops the actor from queueing work for itself.
fn (wr &Runtime) refuse_nested(name string) {
	if wr.on_actor_thread() {
		panic('world "${wr.name_}": "${name}" was queued from the actor thread; use Tx.defer, or a transaction on the other world')
	}
}

// close stops the world. Work already queued still runs and nothing new is
// accepted. It waits for the actor to finish.
pub fn (mut wr Runtime) close() {
	wr.queueing.lock()
	if wr.closed.load() != 0 {
		wr.queueing.unlock()
		return
	}
	wr.closed.store(1)
	wr.tasks.close()
	wr.queueing.unlock()
	_ := <-wr.done or { false }
}

// defer queues work to run on this world after the current callback returns and
// before the task is done, in the order it was queued. Use it for follow-up
// work: the actor can't queue a task for itself.
pub fn (mut tx Tx) defer(f fn (mut tx Tx)) {
	tx.ensure_live()
	tx.deferred << f
}

// ensure_live panics if the transaction's task is already over. The actor has
// moved on by then, so anything reached through it would be reached from
// whatever thread still holds it.
fn (tx &Tx) ensure_live() {
	if tx.finished {
		panic('world "${tx.world.name_}": a transaction was used after its task finished; keep a Handle or a Ref instead')
	}
}

// world_name is the name of the world this transaction belongs to.
pub fn (tx &Tx) world_name() string {
	tx.ensure_live()
	return tx.world.name_
}

// add puts an entity into this world. The handle is the caller's to keep.
//
// The entity must be in no world: one that another world already holds would
// end up in both of their maps.
pub fn (mut tx Tx) add(h &Handle) {
	tx.ensure_live()
	mut handle := unsafe { h }
	if !isnil(handle.world) {
		panic('world "${tx.world.name_}": entity ${handle.id_} is already in world "${handle.world.name_}"')
	}
	handle.world = tx.world
	tx.world.entities[handle.id_] = handle
}

// remove takes an entity out of this world and hands back its handle, which
// then belongs to no world. Use transfer to move it to another world.
pub fn (mut tx Tx) remove(id u64) ?&Handle {
	tx.ensure_live()
	mut handle := tx.world.entities[id] or { return none }
	tx.world.entities.delete(id)
	handle.world = unsafe { nil }
	return handle
}

// entity is the entity this world holds under an id, if it holds one.
pub fn (tx &Tx) entity(id u64) ?Entity {
	tx.ensure_live()
	h := tx.world.entities[id] or { return none }
	return h.entity
}

// count is how many entities this world holds.
pub fn (tx &Tx) count() int {
	tx.ensure_live()
	return tx.world.entities.len
}
