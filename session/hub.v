module session

import sync
import protocol
import gamedata
import command

@[heap]
pub struct Hub {
mut:
	sessions        map[u64]&NetworkSession
	mutex           &sync.Mutex = sync.new_mutex()
	next_runtime_id u64 = 1
pub mut:
	world_time int
	data       gamedata.GameData
	commands   command.Registry = command.new_registry()
}

pub fn new_hub(data gamedata.GameData) &Hub {
	return &Hub{
		sessions: map[u64]&NetworkSession{}
		mutex:    sync.new_mutex()
		data:     data
		commands: command.new_registry()
	}
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
}

pub fn (mut h Hub) remove(runtime_id u64) {
	h.mutex.lock()
	h.sessions.delete(runtime_id)
	h.mutex.unlock()
}

pub fn (mut h Hub) count() int {
	h.mutex.lock()
	n := h.sessions.len
	h.mutex.unlock()
	return n
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
