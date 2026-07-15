module entity

import sync
import protocol
import protocol.types

// view_radius is the distance in blocks within which an entity's spawn and move
// packets are sent to a player. Beyond it the client never hears about the
// entity, so idle mobs on the far side of the world cost no bandwidth.
const view_radius = f32(64.0)

// Host is the slice of the server the entity Manager needs: a broadcaster to
// send actor packets to every viewer, a radius-limited broadcaster for
// view-distance culling, the shared runtime-id allocator so entities and players
// never collide in id space, and a block query for collision. Hub satisfies it.
pub interface Host {
mut:
	broadcast(p protocol.Packet)
	broadcast_near(x f32, y f32, z f32, radius f32, p protocol.Packet)
	allocate_runtime_id() u64
	get_block(x int, y int, z int) int
}

// Manager owns every live non-player Entity. spawn/despawn are safe from any
// thread (mutex-guarded); tick() runs once per server tick on the Hub actor
// thread, the same place player state is mutated.
@[heap]
pub struct Manager {
mut:
	mutex    &sync.Mutex = sync.new_mutex()
	entities map[u64]&Entity
	host     Host
}

pub fn new_manager(host Host) &Manager {
	return &Manager{
		host: host
	}
}

// spawn creates an entity driven by behaviour at pos, registers it and
// broadcasts its appearance to all viewers. Returns the live Entity.
pub fn (mut m Manager) spawn(behaviour Behaviour, pos types.Vector3) &Entity {
	rid := m.host.allocate_runtime_id()
	mut e := &Entity{
		unique_id:  i64(rid)
		runtime_id: rid
		identifier: behaviour.identifier()
		pos:        pos
		floor_y:    pos.y
		behaviour:  behaviour
	}
	m.mutex.lock()
	m.entities[rid] = e
	m.mutex.unlock()
	m.host.broadcast_near(e.pos.x, e.pos.y, e.pos.z, view_radius, e.spawn_packet())
	return e
}

// despawn removes the entity with runtime_id and tells viewers to drop it.
pub fn (mut m Manager) despawn(runtime_id u64) {
	m.mutex.lock()
	e := m.entities[runtime_id] or {
		m.mutex.unlock()
		return
	}
	m.entities.delete(runtime_id)
	m.mutex.unlock()
	m.host.broadcast(e.despawn_packet())
}

// count reports how many entities are alive.
pub fn (mut m Manager) count() int {
	m.mutex.lock()
	defer { m.mutex.unlock() }
	return m.entities.len
}

// snapshot returns a stable copy of the live entity list. Used to send existing
// entities to a player who just joined.
pub fn (mut m Manager) snapshot() []&Entity {
	m.mutex.lock()
	defer { m.mutex.unlock() }
	mut list := []&Entity{cap: m.entities.len}
	for _, e in m.entities {
		list << e
	}
	return list
}

// tick advances every entity one server tick: run its Behaviour, apply physics,
// remove the dead, and broadcast movement for the ones that moved.
pub fn (mut m Manager) tick() {
	for mut e in m.snapshot() {
		// Killed between ticks via Entity.kill() - despawn here so it leaves
		// m.entities and a RemoveActorPacket goes out, same as an in-tick death.
		if e.dead {
			m.despawn(e.runtime_id)
			continue
		}
		e.age++
		before := e.pos
		e.behaviour.tick(mut e)
		e.apply_physics(mut m.host)
		if e.dead {
			m.despawn(e.runtime_id)
			continue
		}
		if moved(before, e.pos) {
			m.host.broadcast_near(e.pos.x, e.pos.y, e.pos.z, view_radius, e.move_packet())
		}
	}
}

// moved reports whether two positions differ enough to be worth a broadcast.
fn moved(a types.Vector3, b types.Vector3) bool {
	eps := f32(0.0001)
	return abs_f32(a.x - b.x) > eps || abs_f32(a.y - b.y) > eps || abs_f32(a.z - b.z) > eps
}

fn abs_f32(v f32) f32 {
	return if v < 0 { -v } else { v }
}
