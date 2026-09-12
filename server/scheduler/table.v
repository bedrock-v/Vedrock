module scheduler

import sync

// Handler is the live record of one queued task, returned from every schedule
// call so the caller can cancel it later. delay and period are in the ticks of
// whichever clock scheduled it; next_run is the tick it fires on.
@[heap]
pub struct Handler[T] {
	id     int
	delay  i64
	period i64
mut:
	task      T
	next_run  i64
	cancelled bool
}

// id returns the scheduler assigned handle id.
pub fn (h &Handler[T]) id() int {
	return h.id
}

// is_cancelled reports whether the task has been cancelled.
pub fn (h &Handler[T]) is_cancelled() bool {
	return h.cancelled
}

// cancel stops the task from running again. A repeating task will not fire
// after this; a pending delayed task never fires.
pub fn (mut h Handler[T]) cancel() {
	h.cancelled = true
}

// is_repeating reports whether the task reschedules itself after each run.
pub fn (h &Handler[T]) is_repeating() bool {
	return h.period > 0
}

// work is the task itself, for the scheduler that owns this table to run. How
// a task is invoked differs per scheduler; the global one calls run(), a
// world's passes its transaction so the table never calls it.
pub fn (h &Handler[T]) work() T {
	return h.task
}

// Table is the bookkeeping every scheduler shares: ids, due times and
// cancellation, guarded by one mutex. It holds no clock of its own beyond the
// tick it was last run against and it never runs a task.
@[heap]
pub struct Table[T] {
mut:
	mutex        &sync.Mutex = unsafe { nil }
	tasks        map[int]&Handler[T]
	next_id      int = 1
	current_tick i64
}

// new_table builds the table a scheduler owns. It exists because a defaulted
// field initialiser on a generic struct doesn't run when that struct is a
// value field of another one which left the mutex nil and every table method
// locking nothing. Build a Table only through this.
pub fn new_table[T]() Table[T] {
	return Table[T]{
		mutex: sync.new_mutex()
	}
}

// add queues task against a clock the caller owns, such as a world's own
// simulated tick. delay <= 0 means "next tick"; period <= 0 means "run once".
pub fn (mut t Table[T]) add(task T, delay i64, period i64, current_tick i64) &Handler[T] {
	t.mutex.lock()
	id := t.next_id
	t.next_id++
	start := if delay > 0 { current_tick + delay } else { current_tick }
	mut handler := &Handler[T]{
		id:       id
		delay:    delay
		period:   period
		task:     task
		next_run: start
	}
	t.tasks[id] = handler
	t.mutex.unlock()
	return handler
}

// add_now queues task against the tick this table was last run against, for a
// scheduler whose clock is the one it is driven by.
//
// The body repeats add's rather than calling it. A generic method that stores a
// T into a generic struct field is miscompiled when it is emitted for two
// different interface types: the second instantiation's body gets an as_cast to
// the first one's interface. Table is instantiated at both scheduler.Task and
// worldrt.WorldTask, so add and add_now may each be emitted for only one of
// them. Add for WorldTask, add_now for Task. Calling one from the other pulls
// it into both and brings the bug back. Every other method here is emitted for
// both and is fine because none of them store a T.
//
// It breaks the C compile rather than corrupting anything, so a mistake here is
// loud. See CONTRIBUTING for the reproduction.
pub fn (mut t Table[T]) add_now(task T, delay i64, period i64) &Handler[T] {
	t.mutex.lock()
	id := t.next_id
	t.next_id++
	start := if delay > 0 { t.current_tick + delay } else { t.current_tick }
	mut handler := &Handler[T]{
		id:       id
		delay:    delay
		period:   period
		task:     task
		next_run: start
	}
	t.tasks[id] = handler
	t.mutex.unlock()
	return handler
}

// cancel stops and removes the task with the given id, if present. Safe to
// call from any thread.
pub fn (mut t Table[T]) cancel(id int) {
	t.mutex.lock()
	if mut handler := t.tasks[id] {
		handler.cancelled = true
		t.tasks.delete(id)
	}
	t.mutex.unlock()
}

// cancel_all cancels and drops every queued task.
pub fn (mut t Table[T]) cancel_all() {
	t.mutex.lock()
	for _, mut handler in t.tasks {
		handler.cancelled = true
	}
	t.tasks.clear()
	t.mutex.unlock()
}

// count reports how many tasks are queued.
pub fn (mut t Table[T]) count() int {
	t.mutex.lock()
	defer {
		t.mutex.unlock()
	}
	return t.tasks.len
}

// due advances the table's clock to tick and returns the tasks that fire at or
// before it. They are returned rather than run: the caller holds no lock while
// running them, so a task may schedule more work.
pub fn (mut t Table[T]) due(tick i64) []&Handler[T] {
	t.mutex.lock()
	t.current_tick = tick
	mut ready := []&Handler[T]{}
	for _, handler in t.tasks {
		if !handler.cancelled && handler.next_run <= tick {
			ready << handler
		}
	}
	t.mutex.unlock()
	return ready
}

// settle reschedules the repeating tasks that have just run and drops the
// one shots and the cancelled.
pub fn (mut t Table[T]) settle(mut ran []&Handler[T], tick i64) {
	t.mutex.lock()
	for mut handler in ran {
		if handler.cancelled || !handler.is_repeating() {
			t.tasks.delete(handler.id)
		} else {
			handler.next_run = tick + handler.period
		}
	}
	t.mutex.unlock()
}
