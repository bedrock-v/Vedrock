module entity

import sync
import protocol
import protocol.types
import server.world
import server.effect

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
	collision_boxes(x int, y int, z int) []world.AABB
	// entity_position returns the current position of any live actor (player
	// or non player entity) the Host knows about or none if runtime_id no
	// longer exists. Lets a Behaviour target something outside the entity
	// Manager's own bookkeeping without the entity package
	// importing session.
	entity_position(runtime_id u64) ?types.Vector3
	// entity_hit_test returns the runtime id of the first live actor other
	// than exclude_runtime_id whose box contains pos or none. Used for
	// projectile vs entity/player collision.
	entity_hit_test(pos types.Vector3, exclude_runtime_id u64) ?u64
	// damage_entity applies damage to the actor at runtime_id (player or
	// entity), attributed to source_name/source_runtime_id, with
	// knockback_from as the origin used to compute knockback direction.
	damage_entity(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3)
	// nearest_player returns the runtime id of the closest connected player
	// within radius of pos or none if nobody is that close. Used for
	// proactive mob targeting (HostileBehaviour scanning for a target it
	// hasn't been hit by yet).
	nearest_player(pos types.Vector3, radius f32) ?u64
	// notify_entity_despawn lets the entity package announce a despawn.
	notify_entity_despawn(identifier string, x f32, y f32, z f32)
	pickup_item(item_runtime_id u64, stack types.ItemStack, pos types.Vector3) int
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
		effects:    effect.new_manager()
	}
	m.mutex.lock()
	m.entities[rid] = e
	m.mutex.unlock()
	m.host.broadcast_near(e.pos.x, e.pos.y, e.pos.z, view_radius, e.spawn_packet())
	return e
}

pub fn (mut m Manager) spawn_item(stack types.ItemStack, pos types.Vector3, velocity types.Vector3, pickup_delay i64) &Entity {
	rid := m.host.allocate_runtime_id()
	mut e := &Entity{
		unique_id:    i64(rid)
		runtime_id:   rid
		identifier:   'minecraft:item'
		pos:          pos
		velocity:     velocity
		floor_y:      pos.y - 320.0
		behaviour:    &ItemBehaviour{}
		effects:      effect.new_manager()
		item:         stack
		pickup_delay: pickup_delay
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
	m.host.notify_entity_despawn(e.identifier, e.pos.x, e.pos.y, e.pos.z)
}

// by_runtime_id returns the live entity with runtime_id.
pub fn (mut m Manager) by_runtime_id(runtime_id u64) ?&Entity {
	m.mutex.lock()
	defer { m.mutex.unlock() }
	return m.entities[runtime_id] or { none }
}

pub fn (mut m Manager) hit_test(pos types.Vector3, exclude_runtime_id u64) ?u64 {
	for e in m.snapshot() {
		if e.runtime_id == exclude_runtime_id || e.dead {
			continue
		}
		if pos.x >= e.pos.x - entity_half_width && pos.x <= e.pos.x + entity_half_width
			&& pos.z >= e.pos.z - entity_half_width && pos.z <= e.pos.z + entity_half_width
			&& pos.y >= e.pos.y && pos.y <= e.pos.y + entity_height {
			return e.runtime_id
		}
	}
	return none
}

pub fn (mut m Manager) damage(runtime_id u64, amount f32, fatal bool, mut host Host, source_runtime_id u64) {
	m.mutex.lock()
	mut e := m.entities[runtime_id] or {
		m.mutex.unlock()
		return
	}
	m.mutex.unlock()
	e.hurt(mut host, amount, fatal, source_runtime_id)
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
		e.tick_effects(mut m.host)
		if e.dead {
			m.despawn(e.runtime_id)
			continue
		}
		e.behaviour.tick(mut e, mut m.host)
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
