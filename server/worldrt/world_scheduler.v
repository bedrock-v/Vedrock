module worldrt

import server.scheduler

// WorldTaskHandler is the live record of a queued world task, returned from
// every World.run_* call so the caller can cancel it later. delay and period
// are in this world's own simulated ticks.
pub type WorldTaskHandler = scheduler.Handler[WorldTask]

// WorldScheduler runs scheduled tasks against one world's own simulated tick
// clock on that world's own actor thread. A slow or blocking callback here
// only stalls this one world.
//
// The bookkeeping is scheduler.Table, shared with the global scheduler; what
// differs is the call: a world task is handed the transaction it runs in.
@[heap]
pub struct WorldScheduler {
mut:
	table scheduler.Table[WorldTask]
}

pub fn new_world_scheduler() &WorldScheduler {
	return &WorldScheduler{
		table: scheduler.new_table[WorldTask]()
	}
}

// add queues task against this world's own simulated tick, never the global
// one. delay <= 0 means "next simulated step"; period <= 0 means "run once".
pub fn (mut s WorldScheduler) add(task WorldTask, delay i64, period i64, current_tick i64) &WorldTaskHandler {
	return s.table.add(task, delay, period, current_tick)
}

// cancel stops and removes the task with the given id, if present. Safe to
// call from any thread.
pub fn (mut s WorldScheduler) cancel(id int) {
	s.table.cancel(id)
}

pub fn (mut s WorldScheduler) heartbeat(mut tx WorldTx, tick i64) {
	mut due := s.table.due(tick)
	for handler in due {
		if handler.is_cancelled() {
			continue
		}
		mut task := handler.work()
		task.run(mut tx)
	}
	s.table.settle(mut due, tick)
}
