module session

import sync
import sync.stdatomic
import time
import rand
import protocol
import protocol.types
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
// WorldTx for world access.
interface WorldTask {
	run(mut tx WorldTx)
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

	// Coalesces tick requests to at most one pending wakeup.
	tick_wakeup chan bool = chan bool{cap: 1}

	// Shutdown signalling. Runtime channels remain open for their lifetime.
	stop chan bool = chan bool{cap: 1}
	done chan bool = chan bool{cap: 1}

	// Players currently registered with this world, keyed by runtime ID.
	// Access only from this world's runtime thread and modify through WorldTx.
	players map[u64]WorldPlayerEntry

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

	// Cross thread instrumentation snapshots.
	published_tick_runs       &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_simulated_steps &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
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
fn update_block_packet(x int, y int, z int, id int) &protocol.UpdateBlockPacket {
	return &protocol.UpdateBlockPacket{
		block_position:   types.BlockPosition{x, y, z}
		block_runtime_id: id
		flags:            block_update_flags
		data_layer_id:    0
	}
}

// broadcast_world sends p to every player registered with this world.
// Call it only from this world's runtime thread, usually inside a WorldTx
// or world_call, because the player registry is not protected by a lock.
fn (mut wr WorldRuntime) broadcast_world(p protocol.Packet) {
	for mut entry in wr.players.values() {
		entry.session.deliver(p)
	}
}

// broadcast_world_except sends p to every player in this world except the
// given runtime ID. Call it only from this world's runtime thread.
fn (mut wr WorldRuntime) broadcast_world_except(except_runtime_id u64, p protocol.Packet) {
	for mut entry in wr.players.values() {
		if entry.session.runtime_id != except_runtime_id {
			entry.session.deliver(p)
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
			return true
		}
		else {
			return false
		}
	}
	return false
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
				task.run(mut tx)
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
							task.run(mut tx)
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
	debt := target - wr.current_tick
	steps := if debt > max_world_catchup_ticks { max_world_catchup_ticks } else { debt }
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
}

// tick_effects advances active effects for players currently registered in
// this world. Effect damage and death stay on the same runtime as the player.
fn (mut tx WorldTx) tick_effects() {
	for mut entry in tx.wr.players.values() {
		entry.session.tick_effects(mut tx.wr)
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
	eprintln('[world ${tx.wr.world.name}] tick overrun: ${debt} ticks behind, catch-up capped at ${max_world_catchup_ticks}')
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

fn (t UnregisterEventTask) run(mut tx WorldTx) {
	tx.wr.events.unregister(t.handler)
}
