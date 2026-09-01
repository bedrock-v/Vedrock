module entity

import bedrock_v.protocol

// Viewer is an actor that can receive packets: a player, as far as anything
// broadcasting to a world is concerned. It exists so world level broadcast
// code can reach the sessions in a world without naming the session type
// which would tie the world to the layer that owns connections.
pub interface Viewer {
	runtime_id() u64
mut:
	deliver(p protocol.Packet)
}

// player_viewers returns every registered player actor that can be sent to.
// Registered mob entities are not viewers and are left out.
pub fn (mut m Manager) player_viewers() []Viewer {
	m.mutex.lock()
	defer {
		m.mutex.unlock()
	}
	mut list := []Viewer{cap: m.actors.len}
	for _, entry in m.actors {
		if entry.actor is Entity {
			continue
		}
		mut a := entry.actor
		if mut a is Viewer {
			list << a
		}
	}
	return list
}
