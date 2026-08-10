module session

import sync
import sync.stdatomic
import time
import rand
import protocol
import protocol.version.v944.packets as packets_944
import server.types
import server.internal.network
import server.block
import server.entity
import server.event
import server.liquid
import server.world.db

// max_world_catchup_ticks limits how many missed simulation steps a
// WorldRuntime replays before advancing directly to the latest requested tick.
const max_world_catchup_ticks = 20

// max_due_updates_per_tick limits scheduled block updates processed in one
// simulation step, preventing large overdue backlogs from monopolizing a tick.
const max_due_updates_per_tick = 64

// WorldLifecycle governs whether a WorldRuntime accepts new work.
enum WorldLifecycle {
	running  // submit()/try_submit() accept and enqueue
	stopping // reject new submissions; in flight submitters still landing, actor still processing what's queued
	closed   // actor loop has exited; safe to close the underlying db.World
}

// WorldTask runs on its owning WorldRuntime's actor thread and receives a
// WorldTx for world access. name identifies the task's concrete type for
// metrics, so a slow task is attributable to a cause rather than showing up
// only as an unexplained tick duration spike.
interface WorldTask {
	run(mut tx WorldTx)
	name() string
}

// WorldRuntime owns one world's actor and serializes its simulation state.
// External callers submit WorldTasks; task code accesses the world through
// WorldTx. Actor owned fields must not be accessed directly from other threads.
@[heap]
struct WorldRuntime {
mut:
	hub   &Hub      = unsafe { nil }
	world &db.World = unsafe { nil }
	// Guards lifecycle state and in flight submission accounting. It must not
	// be held during blocking channel operations.
	mutex     &sync.Mutex = sync.new_mutex()
	lifecycle WorldLifecycle
	inflight  int

	jobs chan WorldTask = chan WorldTask{cap: 256}

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

	liquids  &liquid.LiquidManager = unsafe { nil }
	events   &event.Bus            = unsafe { nil }
	entities &entity.Manager       = unsafe { nil }

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
	// longest_task_name uses the runtime mutex because V atomics can't store
	// strings. It is updated only when a task sets a new duration record.
	longest_task_name string
}

// new_world_runtime creates a runtime for an already loaded world and starts
// its actor thread. Callers must shut it down before releasing all references.
fn new_world_runtime(hub &Hub, w &db.World) &WorldRuntime {
	mut wr := &WorldRuntime{
		hub:   hub
		world: w
	}
	wr.liquids = liquid.new_manager(WorldLiquidHost{ wr: wr })
	wr.events = event.new_bus()
	wr.entities = entity.new_manager(WorldEntityHost{ wr: wr })
	spawn wr.run_jobs()
	return wr
}

// WorldTx provides actor local access to a world's mutable state. It is created
// only by the owning WorldRuntime actor and passed to WorldTasks. Code already
// running inside a task must perform nested work through WorldTx rather than
// submitting another task to the same runtime.
@[heap]
struct WorldTx {
mut:
	wr &WorldRuntime
}

// world returns the underlying db.World for direct reads/writes. Only ever
// reachable through a WorldTx, i.e. only from the owning actor thread.
fn (tx &WorldTx) world() &db.World {
	return tx.wr.world
}

fn (mut tx WorldTx) set_block(x int, y int, z int, id int) {
	tx.wr.world.set_block(x, y, z, id)
	tx.broadcast_block(x, y, z, id)
}

fn (mut tx WorldTx) place_water(x int, y int, z int) {
	tx.wr.liquids.place_source(x, y, z)
}

fn (mut tx WorldTx) on_block_changed(x int, y int, z int) {
	tx.wr.liquids.on_block_changed(x, y, z)
}

fn (mut tx WorldTx) broadcast_block(x int, y int, z int, id int) {
	tx.wr.broadcast_world(update_block_packet(x, y, z, id))
}

// update_block_packet builds the packet both WorldTx.broadcast_block and
// WorldLiquidHost.set_block_id send, avoiding duplicating the field list.
fn update_block_packet(x int, y int, z int, id int) &packets_944.UpdateBlockPacket {
	return &packets_944.UpdateBlockPacket{
		block_position:   network.block_pos_v944(types.BlockPosition{x, y, z})
		block_runtime_id: u32(id)
		flags:            block_update_flags
		layer:            0
	}
}

// broadcast_world sends p to every player registered with this world.
// Call it only from this world's runtime thread, usually inside a WorldTx
// or world_call, because the actor registry is not protected by a lock.
fn (mut wr WorldRuntime) broadcast_world(p protocol.Packet) {
	for mut a in wr.entities.player_actors() {
		if mut a is NetworkSession {
			a.deliver(p)
		}
	}
}

// broadcast_world_except sends p to every player in this world except the
// given runtime ID. Call it only from this world's runtime thread.
fn (mut wr WorldRuntime) broadcast_world_except(except_runtime_id u64, p protocol.Packet) {
	for mut a in wr.entities.player_actors() {
		if mut a is NetworkSession {
			if a.runtime_id != except_runtime_id {
				a.deliver(p)
			}
		}
	}
}

// WorldLiquidHost adapts one WorldRuntime to liquid.Host. Its methods run on
// the owning world actor and mutate world state directly without resubmitting.
struct WorldLiquidHost {
mut:
	wr &WorldRuntime
}

fn (mut h WorldLiquidHost) get_block(x int, y int, z int) int {
	if id := h.wr.world.block_override(x, y, z) {
		return id
	}
	gen := h.wr.world.make_generator(h.wr.hub.build_generator(h.wr.world))
	return gen.block_at(x, y, z)
}

fn (mut h WorldLiquidHost) set_block_id(id int, x int, y int, z int) {
	h.wr.world.set_block(x, y, z, id)
	h.wr.broadcast_world(update_block_packet(x, y, z, id))
}

fn (mut wr WorldRuntime) submit(task WorldTask) bool {
	wr.mutex.lock()
	if wr.lifecycle != .running {
		wr.mutex.unlock()
		return false
	}
	wr.inflight++
	wr.mutex.unlock()

	// The channel remains open for the runtime's lifetime, so this can block
	// only while waiting for queue capacity.
	wr.jobs <- task

	wr.mutex.lock()
	wr.inflight--
	wr.queue_times << time.now()
	wr.mutex.unlock()
	return true
}

// try_submit attempts to queue task without blocking. It returns false if the
// runtime is stopping or the queue has no available capacity.
fn (mut wr WorldRuntime) try_submit(task WorldTask) bool {
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
fn (mut wr WorldRuntime) shutdown() {
	wr.mutex.lock()
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
	wr.mutex.lock()
	wr.lifecycle = .closed
	wr.mutex.unlock()
}

// run_jobs owns this world's actor loop. It serializes world tasks, tick
// processing and shutdown on a single thread.
fn (mut wr WorldRuntime) run_jobs() {
	mut tx := &WorldTx{
		wr: wr
	}
	for {
		select {
			task := <-wr.jobs {
				wr.run_task(mut tx, task)
			}
			_ := <-wr.tick_wakeup {
				tx.run_due_tick()
			}
			_ := <-wr.stop {
				// shutdown waits for all accepted submissions before signalling
				// stop, so this final non blocking drain is exhaustive.
				for {
					select {
						task := <-wr.jobs {
							wr.run_task(mut tx, task)
						}
						_ := <-wr.tick_wakeup {
							tx.run_due_tick()
						}
						else {
							break
						}
					}
				}
				wr.done <- true
				return
			}
		}
	}
}

fn (mut wr WorldRuntime) run_task(mut tx WorldTx, task WorldTask) {
	wr.pop_queue_time() or {}
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
// to the world actor. Tick delivery uses a dedicated channel, so task traffic
// can't delay publication or queue multiple pending wakeups.
fn (mut wr WorldRuntime) request_tick(n i64) {
	wr.tick_mutex.lock()
	wr.latest_tick = n
	wr.tick_mutex.unlock()
	select {
		wr.tick_wakeup <- true {}
		else {}
	}
}

// tick_snapshot returns the latest actor published simulation tick and is safe
// to call from any thread.
fn (wr &WorldRuntime) tick_snapshot() i64 {
	mut p := wr.published_tick
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

fn (wr &WorldRuntime) tick_runs_count() i64 {
	mut runs := wr.published_tick_runs
	return runs.load()
}

// simulated_steps_count reports how many discrete simulated ticks
// advance_tick has actually run, across every call - proves the bounded
// catch-up policy structurally: this grows by at most max_world_catchup_ticks
// per run_due_tick, never by the full debt. Safe to call from any thread.
fn (wr &WorldRuntime) simulated_steps_count() i64 {
	mut steps := wr.published_simulated_steps
	return steps.load()
}

// WorldMetrics is a point in time reading of one world's runtime health,
// meant to answer why a world fell behind: whether it is buried in queued
// tasks, stuck simulating one slow task or genuinely under heavy load from
// entities, liquids or scheduled block updates.
pub struct WorldMetrics {
pub:
	world_name              string
	queued_tasks            int
	oldest_queued_task_age  time.Duration
	current_tick            i64
	tick_runs               i64
	simulated_steps         i64
	catchup_events          i64
	tick_overruns           i64
	last_tick_duration      time.Duration
	longest_task_duration   time.Duration
	longest_task_name       string
	scheduled_backlog       int
	liquid_backlog          int
	entity_count            int
	player_count            i64
	outbound_overflow_count i64
	outbound_peak_depth     i64
}

fn (mut wr WorldRuntime) metrics() WorldMetrics {
	mut oldest_age := time.Duration(0)
	wr.mutex.lock()
	if wr.queue_times.len > 0 {
		oldest_age = time.since(wr.queue_times[0])
	}
	longest_task_name := wr.longest_task_name
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

	return WorldMetrics{
		world_name:              wr.world.name
		queued_tasks:            int(wr.jobs.len)
		oldest_queued_task_age:  oldest_age
		current_tick:            wr.tick_snapshot()
		tick_runs:               tick_runs.load()
		simulated_steps:         simulated_steps.load()
		catchup_events:          catchup_events.load()
		tick_overruns:           tick_overruns.load()
		last_tick_duration:      time.Duration(last_tick_ns.load())
		longest_task_duration:   time.Duration(longest_task_ns.load())
		longest_task_name:       longest_task_name
		scheduled_backlog:       wr.world.scheduled_backlog_count()
		liquid_backlog:          int(liquid_backlog.load())
		entity_count:            wr.entities.count()
		player_count:            player_count.load()
		outbound_overflow_count: outbound_overflow_count.load()
		outbound_peak_depth:     outbound_peak_depth.load()
	}
}

// publish_player_count refreshes the cross thread player count snapshot.
// Called only from register_player/deregister_player, both actor only.
fn (mut wr WorldRuntime) publish_player_count() {
	mut count := wr.published_player_count
	count.store(wr.entities.player_actor_count())
}

// advance_tick owns one centralized catch-up loop - subsystems never run
// their own. If this called w.tick()-equivalent logic, liquids.tick(), and
// a scheduler each with their own independent notion of "how far behind are
// we," a single 20-step catch-up could silently become several times the
// intended work. Instead this simulates real discrete steps one at a time,
// running every discrete subsystem exactly once per step, in the same
// fixed order the previous single actor tick path used: scheduled ticks,
// then random ticks, then liquids, then entities, then publish -
// broadcasting each step's changes before moving to the next so later
// steps in the same call see already-applied state, matching how a real
// 50ms-apart tick would.
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
		wr.liquids.tick()
		wr.entities.tick()
		tx.tick_effects()
	}
	if debt > max_world_catchup_ticks {
		tx.log_tick_overrun(debt)
	}
	wr.current_tick = target // always resync the clock, regardless of how much was actually simulated
	mut p := wr.published_tick
	p.store(wr.current_tick)

	mut liquid_backlog := wr.published_liquid_backlog
	liquid_backlog.store(i64(wr.liquids.pending_count()))
	mut last_tick_ns := wr.published_last_tick_ns
	last_tick_ns.store(time.since(tick_start).nanoseconds())
}

// tick_effects advances active effects for players currently registered in
// this world. Effect damage and death stay on the same runtime as the player.
// It also samples each session's outbound queue depth, since this loop
// already visits every registered player once per simulated step and a
// separate pass would repeat that work purely for metrics.
fn (mut tx WorldTx) tick_effects() {
	for mut a in tx.wr.entities.player_actors() {
		if mut a is NetworkSession {
			a.tick_effects(mut tx.wr)
			a.tick_environmental_damage(mut tx)
			tx.wr.sample_outbound_depth(int(a.outbound.len))
		}
	}
}

fn (mut wr WorldRuntime) sample_outbound_depth(depth int) {
	mut peak := wr.published_outbound_peak_depth
	if i64(depth) > peak.load() {
		peak.store(i64(depth))
	}
}

// run_due_scheduled_ticks executes at most max_due_updates_per_tick entries
// whose deadline has arrived at this simulated step. Deadline advancement
// (which entries are due) is an uncapped elapsed-time comparison, handled
// inside due_scheduled_entries against wr.current_tick; execution is the
// part that needs the bound, since a long stall can make hundreds of
// entries due in the same step.
fn (mut tx WorldTx) run_due_scheduled_ticks() {
	mut wr := tx.wr
	due := wr.world.due_scheduled_entries(wr.current_tick, max_due_updates_per_tick)
	for entry in due {
		old_id := wr.world.block_id(entry.x, entry.y, entry.z)
		b := wr.hub.blocks.get(old_id) or { continue }
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
		b := wr.hub.blocks.get(old_id) or { continue }
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
// max_world_catchup_ticks could absorb. Runtime-level reporting currently uses
// stderr because WorldRuntime does not own a logger.
fn (mut tx WorldTx) log_tick_overrun(debt i64) {
	mut overruns := tx.wr.published_tick_overruns
	overruns.add(1)
	eprintln('[world ${tx.wr.world.name}] tick overrun: ${debt} ticks behind, catch-up capped at ${max_world_catchup_ticks}')
}

fn (mut wr WorldRuntime) record_outbound_overflow() {
	mut overflows := wr.published_outbound_overflow_count
	overflows.add(1)
}

// register_event submits event-bus mutation to the owning runtime so
// registration is serialized against dispatch.
fn (wr &WorldRuntime) register_event(handler event.Handler, priority event.Priority) {
	mut w := unsafe { wr }
	w.submit(RegisterEventTask{
		handler:  handler
		priority: priority
	})
}

struct RegisterEventTask {
	handler  event.Handler
	priority event.Priority
}

fn (t RegisterEventTask) name() string {
	return 'RegisterEventTask'
}

fn (t RegisterEventTask) run(mut tx WorldTx) {
	tx.wr.events.register(t.handler, t.priority)
}

// unregister_event submits event-bus mutation to the owning runtime so removal
// is serialized against dispatch.
fn (wr &WorldRuntime) unregister_event(handler event.Handler) {
	mut w := unsafe { wr }
	w.submit(UnregisterEventTask{
		handler: handler
	})
}

struct UnregisterEventTask {
	handler event.Handler
}

fn (t UnregisterEventTask) name() string {
	return 'UnregisterEventTask'
}

fn (t UnregisterEventTask) run(mut tx WorldTx) {
	tx.wr.events.unregister(t.handler)
}
