module worldrt

import sync
import sync.stdatomic
import time
import rand
import bedrock_v.protocol
import bedrock_v.protocol.types
import server.block
import server.entity
import server.world.db
import server.internal.logger
import bedrock_v.protocol.current as proto

// max_world_catchup_ticks bounds how many simulation steps a WorldRuntime
// replays in a single run_due_tick call. Debt beyond this is not skipped by
// resyncing the clock.
//
// It stays behind and is picked up on the next call, see advance_tick's own comment.
const max_world_catchup_ticks = 20

// max_due_updates_per_tick limits scheduled block updates processed in one
// simulation step, preventing large overdue backlogs from monopolizing a tick.
const max_due_updates_per_tick = 64

// liquid_tick_interval is how many simulation steps pass between liquid flow
// steps. Vanilla water schedules its next update 5 ticks ahead, so the flow
// advances one cell every 5 ticks instead of every tick.
const liquid_tick_interval = 5

// WorldLifecycle governs whether a WorldRuntime accepts new work.
pub enum WorldLifecycle {
	running  // submit()/try_submit() accept and enqueue
	stopping // reject new submissions; in flight submitters still landing, actor still processing what's queued
	closed   // actor loop has exited; safe to close the underlying db.World
}

// WorldTask runs on its owning WorldRuntime's actor thread and receives a
// WorldTx for world access. name identifies the task's concrete type for
// metrics, so a slow task is attributable to a cause rather than showing up
// only as an unexplained tick duration spike.
pub interface WorldTask {
	run(mut tx WorldTx)
	name() string
}

// WorldRuntime owns one world's actor and serializes its simulation state.
// External callers submit WorldTasks; task code accesses the world through
// WorldTx. Actor owned fields must not be accessed directly from other threads.

// block_update_flags is the UpdateBlockPacket flag set every block change is
// sent with: neighbours plus network.
@[heap]
pub const block_update_flags = 11

@[heap]
pub struct WorldRuntime {
pub mut:
	// The shared substrate a world task works on. Public because gameplay code
	// outside this module runs on the actor and needs them; everything below
	// belongs to the actor alone and stays private to it.
	world          &db.World          = unsafe { nil }
	entities       &entity.Manager    = unsafe { nil }
	chunk_service  &WorldChunkService = unsafe { nil }
	task_scheduler &WorldScheduler    = unsafe { nil }
	// services is the slice of the surrounding server a world task may need.
	// The actor's own work never touches it.
	services Services
	// generators resolves this world's generator. Held as the narrow contract
	// rather than as the server type, so the runtime never gains access to
	// sessions through it.
	generators GeneratorFactory
	// handler receives what happens in this world without a player causing it.
	handler Handler              = NopHandler{}
	liquids &block.LiquidManager = unsafe { nil }
mut:
	// players advances the players in this world once per simulated step. The
	// runtime can't do it itself: a player is a session concept.
	players PlayerTicker
	// Guards lifecycle state and in flight submission accounting. It must not
	// be held during blocking channel operations.
	mutex     &sync.Mutex = sync.new_mutex()
	lifecycle WorldLifecycle
	inflight  int

	jobs chan WorldTask = chan WorldTask{cap: 256}

	// Follow up work left behind by a task that yielded part way through a
	// large job. Owned by the actor thread and deliberately unbounded: routing
	// it back through jobs would let a full queue abandon the job halfway.
	continuations []WorldTask

	// Timestamps for tasks waiting in the world queue, ordered oldest first.
	// They are added when a task is queued and removed when the world thread
	// begins processing it, allowing queue wait time to be measured safely.
	queue_times []time.Time

	// Coalesces tick requests to at most one pending wakeup.
	tick_wakeup chan bool = chan bool{cap: 1}

	// Shutdown signalling. Runtime channels remain open for their lifetime.
	stop chan bool = chan bool{cap: 1}
	done chan bool = chan bool{cap: 1}

	// Authoritative simulation tick, owned exclusively by the actor thread.
	current_tick i64

	// Publishes the latest requested global tick to the actor.
	tick_mutex  &sync.Mutex = sync.new_mutex()
	latest_tick i64

	// Cross thread snapshot of current_tick.
	published_tick &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)

	// Cross thread snapshot of latest_tick, lets any thread compute
	// simulation debt (requested - simulated) without taking tick_mutex.
	published_latest_tick &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)

	// Cross thread metric snapshots. The world thread publishes simulation
	// values, session threads publish outbound values and other threads only
	// read them.
	published_tick_runs               &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_simulated_steps         &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_catchup_events          &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_tick_overruns           &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_last_tick_ns            &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_liquid_backlog          &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_player_count            &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_outbound_overflow_count &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_outbound_peak_depth     &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_longest_task_ns         &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	// Continuation backlog, published for metrics because continuations is
	// actor owned and must not be read from another thread. The list is
	// deliberately unbounded (see its own comment), so depth is the only
	// signal that a task is rescheduling itself without making progress.
	published_continuation_depth &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_continuation_peak  &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	// actor_thread identifies the thread running run_jobs, published once
	// before the loop starts. Other threads read it to detect a call that
	// would block waiting for the actor it is already running on. It reads as
	// 0 until the actor starts, so the check fails open rather than wrong.
	actor_thread &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	// longest_task_name uses the runtime mutex because V atomics can't store
	// strings. It is updated only when a task sets a new duration record.
	longest_task_name string
}

// RuntimeConfig is everything a world runtime needs from the layer above it.
// Each field is a narrow contract rather than the server type itself and the
// runtime has no route back to a session.
pub struct RuntimeConfig {
pub:
	world      &db.World = unsafe { nil }
	services   Services
	generators GeneratorFactory
	handler    Handler = NopHandler{}
	players    PlayerTicker
	// entity_host builds the entity manager's host once the runtime exists.
	// A function rather than a value because the host needs the runtime it
	// belongs to.
	entity_host fn (wr &WorldRuntime) entity.Host = unsafe { nil }
}

// new_world_runtime creates a runtime for an already loaded world and starts
// its actor thread. Callers must shut it down before releasing all references.
pub fn new_world_runtime(cfg RuntimeConfig) &WorldRuntime {
	mut wr := &WorldRuntime{
		services:   cfg.services
		handler:    cfg.handler
		generators: cfg.generators
		players:    cfg.players
		world:      cfg.world
	}
	wr.liquids = block.new_manager(WorldLiquidHost{ wr: wr })
	wr.entities = entity.new_manager(cfg.entity_host(wr))
	mut w := cfg.world
	wr.chunk_service = new_chunk_service(w.make_generator(wr.generators.build_generator(w)))
	wr.task_scheduler = new_world_scheduler()
	spawn wr.run_jobs()
	return wr
}

// WorldTx provides actor local access to a world's mutable state. It is created
// only by the owning WorldRuntime actor and passed to WorldTasks. Code already
// running inside a task must perform nested work through WorldTx rather than
// submitting another task to the same runtime.
@[heap]
pub struct WorldTx {
pub mut:
	wr &WorldRuntime
}

// world returns the underlying db.World for direct reads/writes. Only ever
// reachable through a WorldTx, i.e. only from the owning actor thread.
pub fn (tx &WorldTx) world() &db.World {
	return tx.wr.world
}

// resubmit schedules task to run again on this actor after the work already
// queued has had a turn. A task processing a large job in bounded batches uses
// it to yield without risking the remainder being refused by a full queue.
pub fn (mut tx WorldTx) resubmit(task WorldTask) {
	tx.wr.continuations << task
	tx.wr.publish_continuation_depth()
}

// publish_continuation_depth refreshes the cross thread view of the
// continuation backlog and its high water mark. Called only from the actor,
// which is the sole owner of the continuations list.
fn (mut wr WorldRuntime) publish_continuation_depth() {
	depth := i64(wr.continuations.len)
	mut current := wr.published_continuation_depth
	current.store(depth)
	mut peak := wr.published_continuation_peak
	if depth > peak.load() {
		peak.store(depth)
	}
}

// on_actor_thread reports whether the caller is already running on this
// runtime's actor. A blocking call from there waits for work only that same
// thread can perform, then it never completes.
pub fn (wr &WorldRuntime) on_actor_thread() bool {
	mut owner := wr.actor_thread
	id := owner.load()
	return id != 0 && sync.thread_id() == id
}

// generated_block is the generated state of one position, read through the
// world's chunk service so it is the same column every session was sent. A
// generator's per block query and the chunk it builds do not have to agree,
// the chunk carries the populators; the query does not. Asking the
// generator directly can contradict the world the client already has.
pub fn (mut wr WorldRuntime) generated_block(x int, y int, z int) int {
	mut svc := wr.chunk_service
	return svc.block_at(x, y, z)
}

pub fn (mut tx WorldTx) set_block(x int, y int, z int, id int) {
	tx.wr.world.set_block(x, y, z, id)
	tx.broadcast_block(x, y, z, id)
}

pub fn (mut tx WorldTx) place_water(x int, y int, z int) {
	tx.wr.liquids.place_liquid_source(.water, x, y, z)
}

pub fn (mut tx WorldTx) place_lava(x int, y int, z int) {
	tx.wr.liquids.place_liquid_source(.lava, x, y, z)
}

pub fn (mut tx WorldTx) on_block_changed(x int, y int, z int) {
	tx.wr.liquids.on_block_changed(x, y, z)
}

pub fn (mut tx WorldTx) broadcast_block(x int, y int, z int, id int) {
	tx.wr.broadcast_world(update_block_packet(x, y, z, id))
}

// update_block_packet builds the packet both WorldTx.broadcast_block and
// WorldLiquidHost.set_block_id send, avoiding duplicating the field list.
fn update_block_packet(x int, y int, z int, id int) &proto.UpdateBlockPacket {
	return &proto.UpdateBlockPacket{
		block_position:   proto.block_pos(types.BlockPosition{x, y, z})
		block_runtime_id: u32(id)
		flags:            block_update_flags
		layer:            0
	}
}

// handle replaces this world's event handler. Embed NopHandler and
// define only the events the caller cares about.
pub fn (mut wr WorldRuntime) handle(h Handler) {
	wr.handler = h
}

// broadcast_world sends p to every player registered with this world.
// Call it only from this world's runtime thread, usually inside a WorldTx
// or world_call because the actor registry is not protected by a lock.
pub fn (mut wr WorldRuntime) broadcast_world(p protocol.Packet) {
	for mut v in wr.entities.player_viewers() {
		v.deliver(p)
	}
}

// broadcast_world_except sends p to every player in this world except the
// given runtime ID. Call it only from this world's runtime thread.
pub fn (mut wr WorldRuntime) broadcast_world_except(except_runtime_id u64, p protocol.Packet) {
	for mut v in wr.entities.player_viewers() {
		if v.runtime_id() != except_runtime_id {
			v.deliver(p)
		}
	}
}

// WorldLiquidHost adapts one WorldRuntime to block.Host. Its methods run on
// the owning world actor and mutate world state directly without resubmitting.
struct WorldLiquidHost {
mut:
	wr &WorldRuntime
}

fn (mut h WorldLiquidHost) get_block(x int, y int, z int) int {
	if id := h.wr.world.block_override(x, y, z) {
		return id
	}
	gen := h.wr.world.make_generator(h.wr.generators.build_generator(h.wr.world))
	return gen.block_at(x, y, z)
}

fn (mut h WorldLiquidHost) set_block_id(id int, x int, y int, z int) {
	h.wr.world.set_block(x, y, z, id)
	h.wr.broadcast_world(update_block_packet(x, y, z, id))
}

pub fn (mut wr WorldRuntime) submit(task WorldTask) bool {
	wr.mutex.lock()
	if wr.lifecycle != .running {
		wr.mutex.unlock()
		return false
	}
	wr.inflight++
	// Recorded before the send so the actor can't pop this task's turn in the
	// queue before the submitter has written it. A task that waits for
	// capacity is counted as queued for that wait, which is the age an
	// operator asking about backlog wants to see.
	wr.queue_times << time.now()
	wr.mutex.unlock()

	// The channel remains open for the runtime's lifetime, so this can block
	// only while waiting for queue capacity.
	wr.jobs <- task

	wr.mutex.lock()
	wr.inflight--
	wr.mutex.unlock()
	return true
}

// try_submit attempts to queue task without blocking. It returns false if the
// runtime is stopping or the queue has no available capacity.
pub fn (mut wr WorldRuntime) try_submit(task WorldTask) bool {
	wr.mutex.lock()
	defer {
		wr.mutex.unlock()
	}
	if wr.lifecycle != .running {
		return false
	}

	// Holding the lifecycle lock here is safe.
	select {
		wr.jobs <- task {
			wr.queue_times << time.now()
			return true
		}
		else {
			return false
		}
	}
	return false
}

// pop_queue_time consumes the enqueue time of one task, for the oldest queued
// task age in WorldMetrics. Entries are written one per accepted submission,
// so only a task received from the jobs channel may consume one. A
// continuation is actor owned follow up work that was never submitted and
// popping for one would retire the turn of a task still waiting in the queue.
fn (mut wr WorldRuntime) pop_queue_time() ?time.Time {
	wr.mutex.lock()
	defer {
		wr.mutex.unlock()
	}
	if wr.queue_times.len == 0 {
		return none
	}
	t := wr.queue_times[0]
	wr.queue_times.delete(0)
	return t
}

// shutdown stops accepting work, waits for accepted submissions to finish
// enqueueing, signals the actor to exit and returns after shutdown completes.
//
// Runtime channels remain open for their lifetime. Lifecycle state and
// in flight submission tracking provide safe shutdown without racing sends
// against channel closure.
//
// Shutdown is graceful and may block indefinitely if an active task or
// in flight submitter never completes.
pub fn (mut wr WorldRuntime) shutdown() {
	wr.mutex.lock()
	if wr.lifecycle != .running {
		wr.mutex.unlock()
		return
	}
	wr.lifecycle = .stopping
	wr.mutex.unlock()
	for {
		wr.mutex.lock()
		remaining := wr.inflight
		wr.mutex.unlock()
		if remaining == 0 {
			break
		}
		// World shutdown is a cold path, so a short poll is sufficient here.
		time.sleep(1 * time.millisecond)
	}
	wr.stop <- true
	_ := <-wr.done
	wr.chunk_service.shutdown()
	wr.mutex.lock()
	wr.lifecycle = .closed
	wr.mutex.unlock()
}

// run_jobs owns this world's actor loop. It serializes world tasks, tick
// processing and shutdown on a single thread.
fn (mut wr WorldRuntime) run_jobs() {
	logger.name_thread('World Thread/${wr.world.name}')
	mut owner := wr.actor_thread
	owner.store(sync.thread_id())
	defer {
		logger.unname_thread()
	}
	mut tx := &WorldTx{
		wr: wr
	}
	for {
		if wr.continuations.len > 0 {
			// A yielded job is still outstanding. Give the queue and the tick
			// wakeup a turn without blocking on them, then advance that job by
			// one more step so it finishes even while the world stays busy.
			if !wr.poll_once(mut tx) {
				return
			}
			wr.run_continuation(mut tx)
			continue
		}
		if !wr.wait_once(mut tx) {
			return
		}
	}
}

// poll_once handles at most one pending job, tick or stop signal and returns
// false once the actor has shut down.
fn (mut wr WorldRuntime) poll_once(mut tx WorldTx) bool {
	select {
		task := <-wr.jobs {
			wr.pop_queue_time() or {}
			wr.run_task(mut tx, task)
		}
		_ := <-wr.tick_wakeup {
			tx.run_due_tick()
		}
		_ := <-wr.stop {
			wr.finish(mut tx)
			return false
		}
		else {}
	}
	return true
}

// wait_once is poll_once for an idle actor: it blocks until there is something
// to do rather than spinning.
fn (mut wr WorldRuntime) wait_once(mut tx WorldTx) bool {
	select {
		task := <-wr.jobs {
			wr.pop_queue_time() or {}
			wr.run_task(mut tx, task)
		}
		_ := <-wr.tick_wakeup {
			tx.run_due_tick()
		}
		_ := <-wr.stop {
			wr.finish(mut tx)
			return false
		}
	}
	return true
}

fn (mut wr WorldRuntime) run_continuation(mut tx WorldTx) {
	if wr.continuations.len == 0 {
		return
	}
	task := wr.continuations[0]
	wr.continuations.delete(0)
	wr.publish_continuation_depth()
	wr.run_task(mut tx, task)
}

// finish drains everything still outstanding before the actor exits. Shutdown
// waits for all accepted submissions before signalling stop, so the queue drain
// is exhaustive; continuations are run to completion so a half applied job does
// not survive into the saved world.
fn (mut wr WorldRuntime) finish(mut tx WorldTx) {
	for {
		mut idle := false
		select {
			task := <-wr.jobs {
				wr.pop_queue_time() or {}
				wr.run_task(mut tx, task)
			}
			_ := <-wr.tick_wakeup {
				tx.run_due_tick()
			}
			else {
				idle = true
			}
		}
		if !idle {
			continue
		}
		if wr.continuations.len == 0 {
			break
		}
		wr.run_continuation(mut tx)
	}
	wr.done <- true
}

fn (mut wr WorldRuntime) run_task(mut tx WorldTx, task WorldTask) {
	start := time.now()
	task.run(mut tx)
	dur := time.since(start).nanoseconds()

	mut longest := wr.published_longest_task_ns
	if dur > longest.load() {
		longest.store(dur)
		wr.mutex.lock()
		wr.longest_task_name = task.name()
		wr.mutex.unlock()
	}
}

// request_tick publishes the latest requested tick and sends a coalesced wakeup
// to the world actor. Tick delivery uses a dedicated channel. Task traffic
// can't delay publication or queue multiple pending wakeups.
pub fn (mut wr WorldRuntime) request_tick(n i64) {
	wr.tick_mutex.lock()
	wr.latest_tick = n
	// Stored inside the same critical section as latest_tick, not after.
	mut published_latest := wr.published_latest_tick
	published_latest.store(n)
	wr.tick_mutex.unlock()
	select {
		wr.tick_wakeup <- true {}
		else {}
	}
}

// tick_snapshot returns the latest actor published simulation tick and is safe
// to call from any thread.
pub fn (wr &WorldRuntime) tick_snapshot() i64 {
	mut p := wr.published_tick
	return p.load()
}

// requested_tick_locked reads the requested tick under the lock that publishes
// it. requested_tick_snapshot is the lock free path; this is the value it has
// to agree with and exists to that agreement can be asserted.
pub fn (mut wr WorldRuntime) requested_tick_locked() i64 {
	wr.tick_mutex.lock()
	defer {
		wr.tick_mutex.unlock()
	}
	return wr.latest_tick
}

// requested_tick_snapshot returns the latest requested (not yet necessarily
// simulated) tick and is safe to call from any thread. requested_tick_snapshot()
// minus tick_snapshot() is the world's current simulation debt.
pub fn (wr &WorldRuntime) requested_tick_snapshot() i64 {
	mut p := wr.published_latest_tick
	return p.load()
}

fn (mut tx WorldTx) run_due_tick() {
	mut wr := tx.wr
	wr.tick_mutex.lock()
	target := wr.latest_tick
	wr.tick_mutex.unlock()
	tx.advance_tick(target)

	mut runs := wr.published_tick_runs
	runs.add(1)
}

pub fn (wr &WorldRuntime) tick_runs_count() i64 {
	mut runs := wr.published_tick_runs
	return runs.load()
}

// simulated_steps_count reports how many discrete simulated ticks
// advance_tick has actually run, across every call. Proves the bounded
// catchup policy structurally: this grows by at most max_world_catchup_ticks
// per run_due_tick, never by the full debt. Safe to call from any thread.
pub fn (wr &WorldRuntime) simulated_steps_count() i64 {
	mut steps := wr.published_simulated_steps
	return steps.load()
}

// WorldMetrics is a point in time reading of one world's runtime health,
// meant to answer why a world fell behind: whether it is buried in queued
// tasks, stuck simulating one slow task or genuinely under heavy load from
// entities, liquids or scheduled block updates.
pub struct WorldMetrics {
pub:
	world_name                     string
	queued_tasks                   int
	oldest_queued_task_age         time.Duration
	current_tick                   i64
	requested_tick                 i64
	simulation_debt_ticks          i64
	tick_runs                      i64
	simulated_steps                i64
	catchup_events                 i64
	tick_overruns                  i64
	last_tick_duration             time.Duration
	longest_task_duration          time.Duration
	longest_task_name              string
	scheduled_backlog              int
	liquid_backlog                 int
	entity_count                   int
	player_count                   i64
	outbound_overflow_count        i64
	outbound_peak_depth            i64
	persist_pending_count          int
	persist_oldest_pending_ms      i64
	persist_enqueued_total         i64
	persist_committed_total        i64
	persist_pressure_level         int
	persist_high_water_threshold   int
	persist_hard_ceiling_threshold int
	persist_last_write_ms          i64
	persist_longest_write_ms       i64
	persist_consecutive_errors     i64
	chunk_cached_count             int
	chunk_cached_bytes             i64
	chunk_cache_budget_bytes       i64
	chunk_inflight_count           int
	chunk_oldest_inflight_ms       i64
	chunk_active_workers           i64
	chunk_worker_limit             int
	chunk_queue_depth              i64
	chunk_requests_total           i64
	chunk_dedup_hits_total         i64
	actor_running                  bool
	// Continuation backlog now and at its high water mark. Continuations are
	// actor owned follow up work for tasks that yielded; a depth that keeps
	// climbing means something is rescheduling itself faster than it retires.
	continuation_depth i64
	continuation_peak  i64
}

pub fn (mut wr WorldRuntime) metrics() WorldMetrics {
	mut oldest_age := time.Duration(0)
	wr.mutex.lock()
	if wr.queue_times.len > 0 {
		oldest_age = time.since(wr.queue_times[0])
	}
	longest_task_name := wr.longest_task_name
	actor_running := wr.lifecycle == .running
	wr.mutex.unlock()

	mut tick_runs := wr.published_tick_runs
	mut simulated_steps := wr.published_simulated_steps
	mut catchup_events := wr.published_catchup_events
	mut tick_overruns := wr.published_tick_overruns
	mut last_tick_ns := wr.published_last_tick_ns
	mut liquid_backlog := wr.published_liquid_backlog
	mut player_count := wr.published_player_count
	mut outbound_overflow_count := wr.published_outbound_overflow_count
	mut outbound_peak_depth := wr.published_outbound_peak_depth
	mut longest_task_ns := wr.published_longest_task_ns
	mut continuation_depth := wr.published_continuation_depth
	mut continuation_peak := wr.published_continuation_peak
	chunk_metrics := wr.chunk_service.metrics()

	current_tick_val := wr.tick_snapshot()
	requested_tick_val := wr.requested_tick_snapshot()

	return WorldMetrics{
		world_name:                     wr.world.name
		queued_tasks:                   int(wr.jobs.len)
		oldest_queued_task_age:         oldest_age
		current_tick:                   current_tick_val
		requested_tick:                 requested_tick_val
		simulation_debt_ticks:          requested_tick_val - current_tick_val
		tick_runs:                      tick_runs.load()
		simulated_steps:                simulated_steps.load()
		catchup_events:                 catchup_events.load()
		tick_overruns:                  tick_overruns.load()
		last_tick_duration:             time.Duration(last_tick_ns.load())
		longest_task_duration:          time.Duration(longest_task_ns.load())
		longest_task_name:              longest_task_name
		scheduled_backlog:              wr.world.scheduled_backlog_count()
		liquid_backlog:                 int(liquid_backlog.load())
		entity_count:                   wr.entities.count()
		player_count:                   player_count.load()
		outbound_overflow_count:        outbound_overflow_count.load()
		outbound_peak_depth:            outbound_peak_depth.load()
		persist_pending_count:          wr.world.pending_persist_count()
		persist_oldest_pending_ms:      wr.world.oldest_pending_persist_age().milliseconds()
		persist_enqueued_total:         wr.world.persist_enqueued_total()
		persist_committed_total:        wr.world.persist_committed_total()
		persist_pressure_level:         wr.world.persist_pressure_level()
		persist_high_water_threshold:   wr.world.persist_high_water_threshold_value()
		persist_hard_ceiling_threshold: wr.world.persist_hard_ceiling_threshold_value()
		persist_last_write_ms:          wr.world.last_persist_write_duration().milliseconds()
		persist_longest_write_ms:       wr.world.longest_persist_write_duration().milliseconds()
		persist_consecutive_errors:     wr.world.persist_consecutive_errors()
		chunk_cached_count:             chunk_metrics.cached_chunks
		chunk_cached_bytes:             chunk_metrics.cached_bytes_estimate
		chunk_cache_budget_bytes:       chunk_metrics.cache_budget_bytes
		chunk_inflight_count:           chunk_metrics.inflight_requests
		chunk_oldest_inflight_ms:       chunk_metrics.oldest_inflight_age.milliseconds()
		chunk_active_workers:           chunk_metrics.active_workers
		chunk_worker_limit:             chunk_metrics.worker_limit
		chunk_queue_depth:              chunk_metrics.queue_depth
		chunk_requests_total:           chunk_metrics.requests_total
		chunk_dedup_hits_total:         chunk_metrics.dedup_hits_total
		actor_running:                  actor_running
		continuation_depth:             continuation_depth.load()
		continuation_peak:              continuation_peak.load()
	}
}

// publish_player_count refreshes the cross thread player count snapshot.
// Called only from register_player/deregister_player, both actor only.
pub fn (mut wr WorldRuntime) publish_player_count() {
	mut count := wr.published_player_count
	count.store(wr.entities.player_actor_count())
}

// player_count returns the latest published player count for this world.
// It is thread safe and does not block on the world actor.
pub fn (wr &WorldRuntime) player_count() i64 {
	mut count := wr.published_player_count
	return count.load()
}

fn (mut tx WorldTx) advance_tick(target i64) {
	mut wr := tx.wr
	tick_start := time.now()
	debt := target - wr.current_tick
	steps := if debt > max_world_catchup_ticks { max_world_catchup_ticks } else { debt }
	if steps > 1 {
		mut catchup := wr.published_catchup_events
		catchup.add(1)
	}
	for _ in 0 .. steps {
		wr.current_tick++
		mut simulated := wr.published_simulated_steps
		simulated.add(1)
		tx.run_due_scheduled_ticks()
		tx.run_random_ticks()
		if wr.current_tick % liquid_tick_interval == 0 {
			wr.liquids.tick()
		}
		wr.entities.tick()
		wr.players.tick_players(mut tx)
		wr.task_scheduler.heartbeat(mut tx, wr.current_tick)
	}
	if debt > max_world_catchup_ticks {
		tx.log_tick_overrun(debt)
	}

	mut p := wr.published_tick
	p.store(wr.current_tick)

	mut liquid_backlog := wr.published_liquid_backlog
	liquid_backlog.store(i64(wr.liquids.pending_count()))
	mut last_tick_ns := wr.published_last_tick_ns
	last_tick_ns.store(time.since(tick_start).nanoseconds())
}

pub fn (mut wr WorldRuntime) sample_outbound_depth(depth int) {
	mut peak := wr.published_outbound_peak_depth
	if i64(depth) > peak.load() {
		peak.store(i64(depth))
	}
}

fn (mut tx WorldTx) run_due_scheduled_ticks() {
	mut wr := tx.wr
	due := wr.world.due_scheduled_entries(wr.current_tick, max_due_updates_per_tick)
	for entry in due {
		old_id := wr.world.block_id(entry.x, entry.y, entry.z)
		b := block.get(old_id) or { continue }
		if b is block.ScheduledTicker {
			b.scheduled_tick(entry.x, entry.y, entry.z, mut wr.world)
			new_id := wr.world.block_id(entry.x, entry.y, entry.z)
			if new_id != old_id {
				tx.broadcast_block(entry.x, entry.y, entry.z, new_id)
			}
		}
	}
}

fn (mut tx WorldTx) run_random_ticks() {
	mut wr := tx.wr
	positions := wr.world.override_positions()
	for pos in positions {
		chance := rand.intn(block.random_tick_chance_denominator) or { continue }
		if chance >= block.random_tick_speed {
			continue
		}
		old_id := wr.world.block_id(pos.x, pos.y, pos.z)
		b := block.get(old_id) or { continue }
		if b is block.RandomTicker {
			b.random_tick(pos.x, pos.y, pos.z, mut wr.world)
			new_id := wr.world.block_id(pos.x, pos.y, pos.z)
			if new_id != old_id {
				tx.broadcast_block(pos.x, pos.y, pos.z, new_id)
			}
		}
	}
}

// log_tick_overrun records that this world fell behind further than
// max_world_catchup_ticks could absorb.
fn (mut tx WorldTx) log_tick_overrun(debt i64) {
	mut overruns := tx.wr.published_tick_overruns
	overruns.add(1)
	eprintln('[world ${tx.wr.world.name}] tick overrun: ${debt} ticks behind, catch-up capped at ${max_world_catchup_ticks}')
}

pub fn (mut wr WorldRuntime) record_outbound_overflow() {
	mut overflows := wr.published_outbound_overflow_count
	overflows.add(1)
}
