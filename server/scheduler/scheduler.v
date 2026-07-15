module scheduler

import sync

// Scheduler runs Tasks against the server tick clock. It is inspired by
// PocketMine's TaskScheduler but made thread-safe: Vedrock schedules from many
// session threads and plugins, while heartbeat() runs on the single tick actor
// thread. A mutex guards the task table; tasks themselves run outside the lock
// so a task may safely schedule more work.
@[heap]
pub struct Scheduler {
mut:
	mutex        &sync.Mutex = sync.new_mutex()
	tasks        map[int]&TaskHandler
	current_tick i64
	next_id      int = 1
}

pub fn new_scheduler() &Scheduler {
	return &Scheduler{}
}

// run_task queues task to run on the next tick.
pub fn (mut s Scheduler) run_task(task Task) &TaskHandler {
	return s.add(task, 0, 0)
}

// run_delayed queues task to run once, delay ticks from now.
pub fn (mut s Scheduler) run_delayed(task Task, delay i64) &TaskHandler {
	return s.add(task, delay, 0)
}

// run_repeating queues task to run every period ticks, starting next tick.
pub fn (mut s Scheduler) run_repeating(task Task, period i64) &TaskHandler {
	return s.add(task, 0, period)
}

// run_delayed_repeating queues task to first run after delay ticks, then every
// period ticks.
pub fn (mut s Scheduler) run_delayed_repeating(task Task, delay i64, period i64) &TaskHandler {
	return s.add(task, delay, period)
}

// add is the single insertion point. delay <= 0 means "next tick"; period <= 0
// means "run once".
fn (mut s Scheduler) add(task Task, delay i64, period i64) &TaskHandler {
	s.mutex.lock()
	id := s.next_id
	s.next_id++
	start := if delay > 0 { s.current_tick + delay } else { s.current_tick }
	mut handler := &TaskHandler{
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

// cancel stops and removes the task with the given id, if present.
pub fn (mut s Scheduler) cancel(id int) {
	s.mutex.lock()
	if mut handler := s.tasks[id] {
		handler.cancelled = true
		s.tasks.delete(id)
	}
	s.mutex.unlock()
}

// cancel_all cancels and drops every queued task.
pub fn (mut s Scheduler) cancel_all() {
	s.mutex.lock()
	for _, mut handler in s.tasks {
		handler.cancelled = true
	}
	s.tasks.clear()
	s.mutex.unlock()
}

// count reports how many tasks are queued.
pub fn (mut s Scheduler) count() int {
	s.mutex.lock()
	defer { s.mutex.unlock() }
	return s.tasks.len
}

// heartbeat advances the clock to tick and runs every task due at or before it.
// Called once per server tick from the tick actor thread. Due tasks are
// collected under the lock, then run unlocked; repeating tasks are rescheduled
// and one-shots removed afterwards.
pub fn (mut s Scheduler) heartbeat(tick i64) {
	s.mutex.lock()
	s.current_tick = tick
	mut due := []&TaskHandler{}
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
		handler.task.run()
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
