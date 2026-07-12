module session

import sync
import sync.stdatomic
import math
import time
import protocol
import server.internal.gamedata
import server.item
import server.block
import server.internal.language
import server.cmd
import server.cmd.default as defaultcmd
import server.world.db
import server.permission

@[heap]
pub struct Hub {
mut:
	sessions        map[u64]&NetworkSession
	mutex           &sync.Mutex   = sync.new_mutex()
	next_runtime_id u64           = 1
	// jobs is the only door into gameplay-mutable state that spans sessions
	// (combat, targeted /gamemode, etc.). run_jobs() is the sole consumer.
	jobs chan WorldJob = chan WorldJob{cap: 256}
	tps_bits  &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](math.f64_bits(20.0))
	load_bits &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	online_count &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
pub mut:
	world_time   int
	data         gamedata.GameData
	items        item.Registry    = item.new_registry()
	blocks       block.Registry   = block.new_registry()
	lang         &language.Lang   = unsafe { nil }
	commands     cmd.Registry     = cmd.new_registry()
	started_at   i64
	world_blocks map[string]int
	world_store  &db.WorldStore = unsafe { nil }
	ops          permission.OpList
	player_grants permission.PlayerGrants
	whitelist    permission.Whitelist
	// needs vedrock.yml storage.
	difficulty   int = protocol.difficulty_easy
}

pub fn (mut h Hub) tps() f64 {
	return math.f64_from_bits(h.tps_bits.load())
}

fn (mut h Hub) set_tps(v f64) {
	h.tps_bits.store(math.f64_bits(v))
}

pub fn (mut h Hub) load() f64 {
	return math.f64_from_bits(h.load_bits.load())
}

fn (mut h Hub) set_load(v f64) {
	h.load_bits.store(math.f64_bits(v))
}

pub fn new_hub(data gamedata.GameData) &Hub {
	mut commands := cmd.new_registry()
	defaultcmd.register_all(mut commands)
	mut hub := &Hub{
		sessions:   map[u64]&NetworkSession{}
		mutex:      sync.new_mutex()
		data:       data
		commands:   commands
		started_at: time.now().unix()
	}
	spawn hub.run_jobs()
	return hub
}

pub fn (h &Hub) uptime_seconds() i64 {
	return time.now().unix() - h.started_at
}

fn block_key(x int, y int, z int) string {
	return '${x}:${y}:${z}'
}

pub fn (mut h Hub) set_world_block(x int, y int, z int, runtime_id int) {
	h.mutex.lock()
	h.world_blocks[block_key(x, y, z)] = runtime_id
	h.mutex.unlock()
	if !isnil(h.world_store) {
		h.world_store.set_block(x, y, z, runtime_id)
	}
}

pub fn (mut h Hub) load_world() {
	if isnil(h.world_store) {
		return
	}
	h.world_store.each_block(fn [mut h] (x int, y int, z int, runtime_id int) {
		h.world_blocks[block_key(x, y, z)] = runtime_id
	})
}

pub fn (h &Hub) world_block_override(x int, y int, z int) ?int {
	return h.world_blocks[block_key(x, y, z)] or { return none }
}

pub fn (h &Hub) world_block_count() int {
	return h.world_blocks.len
}

pub struct BlockOverride {
pub:
	x  int
	y  int
	z  int
	id int
}

pub fn (mut h Hub) overrides_in_chunk(cx int, cz int) []BlockOverride {
	mut out := []BlockOverride{}
	h.mutex.lock()
	for key, id in h.world_blocks {
		parts := key.split(':')
		if parts.len != 3 {
			continue
		}
		x := parts[0].int()
		z := parts[2].int()
		if (x >> 4) == cx && (z >> 4) == cz {
			out << BlockOverride{
				x:  x
				y:  parts[1].int()
				z:  z
				id: id
			}
		}
	}
	h.mutex.unlock()
	return out
}

pub fn (mut h Hub) allocate_runtime_id() u64 {
	h.mutex.lock()
	id := h.next_runtime_id
	h.next_runtime_id++
	h.mutex.unlock()
	return id
}

pub fn (mut h Hub) add(target &NetworkSession) {
	h.mutex.lock()
	h.sessions[target.runtime_id] = target
	h.mutex.unlock()
	h.online_count.add(1)
}

pub fn (mut h Hub) remove(runtime_id u64) {
	h.mutex.lock()
	h.sessions.delete(runtime_id)
	h.mutex.unlock()
	h.online_count.sub(1)
}

pub fn (mut h Hub) session_by_runtime(runtime_id u64) ?&NetworkSession {
	h.mutex.lock()
	target := h.sessions[runtime_id] or {
		h.mutex.unlock()
		return none
	}
	h.mutex.unlock()
	return target
}

pub fn (mut h Hub) session_by_name(name string) ?&NetworkSession {
	h.mutex.lock()
	defer { h.mutex.unlock() }
	// I'm not sure about trim_space().to_lower(), so let's use casual to_lower
	needle := name.to_lower()
	for _, target in h.sessions {
		if target.identity.display_name.to_lower() == needle {
			return target
		}
	}
	return none
}

pub fn (mut h Hub) count() int {
	return int(h.online_count.load())
}

fn (mut h Hub) snapshot() []&NetworkSession {
	h.mutex.lock()
	mut list := []&NetworkSession{cap: h.sessions.len}
	for _, target in h.sessions {
		list << target
	}
	h.mutex.unlock()
	return list
}

pub fn (mut h Hub) broadcast(p protocol.Packet) {
	for mut target in h.snapshot() {
		target.deliver(p)
	}
}

pub fn (mut h Hub) broadcast_except(runtime_id u64, p protocol.Packet) {
	for mut target in h.snapshot() {
		if target.runtime_id != runtime_id {
			target.deliver(p)
		}
	}
}

pub fn (mut h Hub) disconnect_all(message string) {
	for mut target in h.snapshot() {
		target.disconnect(message)
	}
}

// submit queues a WorldJob for run_jobs() to execute. Blocks if the queue is full.
pub fn (mut h Hub) submit(job WorldJob) {
	h.jobs <- job
}

// run_jobs is the single owner thread for gameplay-mutable state that spans
// sessions. Nothing else may run a WorldJob's run().
fn (mut h Hub) run_jobs() {
	for {
		job := <-h.jobs or { break }
		job.run(mut h)
	}
}
