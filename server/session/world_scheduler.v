module session

import sync

// WorldScheduler runs scheduled tasks against one world's own simulated
// tick clock on that world's own actor thread. A slow or blocking
// callback here only stalls this one world.
//
// Kept separate from the global scheduler.Scheduler on purpose, not
// unified into a generic Scheduler[T] - see CONTRIBUTING.md:Observed V compiler and language behaviors
@[heap]
struct WorldScheduler {
mut:
	mutex   &sync.Mutex = sync.new_mutex()
	tasks   map[int]&WorldTaskHandler
	next_id int = 1
}

fn new_world_scheduler() &WorldScheduler {
	return &WorldScheduler{}
}

// add is the single insertion point. delay <= 0 means "next simulated
// step"; period <= 0 means "run once". current_tick is the world's own
// simulated tick, never the global tick.
fn (mut s WorldScheduler) add(task WorldTask, delay i64, period i64, current_tick i64) &WorldTaskHandler {
	s.mutex.lock()
	id := s.next_id
	s.next_id++
	start := if delay > 0 { current_tick + delay } else { current_tick }
	mut handler := &WorldTaskHandler{
		id:       id
		delay:    delay
		period:   period
		task:     task
		next_run: start
	}
	s.tasks[id] = handler
	s.mutex.unlock()
	return handler
}

// cancel stops and removes the task with the given id, if present. Safe to
// call from any thread.
pub fn (mut s WorldScheduler) cancel(id int) {
	s.mutex.lock()
	if mut handler := s.tasks[id] {
		handler.cancelled = true
		s.tasks.delete(id)
	}
	s.mutex.unlock()
}

fn (mut s WorldScheduler) heartbeat(mut tx WorldTx, tick i64) {
	s.mutex.lock()
	mut due := []&WorldTaskHandler{}
	for _, handler in s.tasks {
		if !handler.cancelled && handler.next_run <= tick {
			due << handler
		}
	}
	s.mutex.unlock()

	for mut handler in due {
		if handler.is_cancelled() {
			continue
		}
		handler.task.run(mut tx)
	}

	s.mutex.lock()
	for mut handler in due {
		if handler.cancelled || !handler.is_repeating() {
			s.tasks.delete(handler.id)
		} else {
			handler.next_run = tick + handler.period
		}
	}
	s.mutex.unlock()
}

// WorldTaskHandler is the world scheduler's live record of a queued task,
// returned from every World.run_* call so the caller can cancel it later.
// delay/period are in this world's own simulated ticks.
@[heap]
pub struct WorldTaskHandler {
	id     int
	delay  i64
	period i64
mut:
	task      WorldTask
	next_run  i64
	cancelled bool
}

pub fn (h &WorldTaskHandler) id() int {
	return h.id
}

pub fn (h &WorldTaskHandler) is_cancelled() bool {
	return h.cancelled
}

// cancel stops the task from running again. A repeating task won't fire
// after this; a pending delayed task never fires.
pub fn (mut h WorldTaskHandler) cancel() {
	h.cancelled = true
}

pub fn (h &WorldTaskHandler) is_repeating() bool {
	return h.period > 0
}

struct WorldClosureTask {
	callback fn (mut tx WorldTransaction) @[required]
}

fn (t WorldClosureTask) name() string {
	return 'WorldClosureTask'
}

fn (t WorldClosureTask) run(mut tx WorldTx) {
	mut handle := WorldTransaction(&WorldTxHandle{
		tx: &tx
	})
	t.callback(mut handle)
}
