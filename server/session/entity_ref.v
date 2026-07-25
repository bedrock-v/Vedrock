module session

import protocol.types
import server.world

// EntityRefSnapshot captures the entity state needed by EntityRef reads.
// It is collected on the owning world thread.
struct EntityRefSnapshot {
	found bool
	pos   types.Vector3
}

// EntityRef is a stale checked reference to a non-player entity. Its
// operations run on the owning world thread without exposing raw entity
// pointers across threads.
//
// Runtime IDs are process wide and never reused, so registration alone is
// sufficient to determine whether the reference is still valid.
pub struct EntityRef {
	runtime_id u64
	world_     World
}

// entity_ref looks up runtime_id in this world's entity manager and
// returns an EntityRef for it or none if no such entity is currently
// registered here.
pub fn (mut w World) entity_ref(runtime_id u64) ?EntityRef {
	found := world_call[bool](mut w.runtime, fn [runtime_id] (mut tx WorldTx) bool {
		tx.wr.entities.by_runtime_id(runtime_id) or { return false }
		return true
	}) or { return none }
	if !found {
		return none
	}
	return EntityRef{
		runtime_id: runtime_id
		world_:     w
	}
}

// world is the World captured at construction.
pub fn (e EntityRef) world() World {
	return e.world_
}

// valid reports whether the entity is still registered in its world, a
// despawned or never existing runtime id reports false.
pub fn (e EntityRef) valid() bool {
	mut w := e.world_
	return world_call[bool](mut w.runtime, fn [e] (mut tx WorldTx) bool {
		tx.wr.entities.by_runtime_id(e.runtime_id) or { return false }
		return true
	}) or { false }
}

pub fn (e EntityRef) position() !world.Vec3 {
	mut w := e.world_
	snap := world_call[EntityRefSnapshot](mut w.runtime, fn [e] (mut tx WorldTx) EntityRefSnapshot {
		target := tx.wr.entities.by_runtime_id(e.runtime_id) or { return EntityRefSnapshot{} }
		return EntityRefSnapshot{
			found: true
			pos:   target.pos
		}
	}) or { return error('world "${e.world_.name()}" is shutting down') }
	if !snap.found {
		return error('entity is no longer registered')
	}
	return world.Vec3{snap.pos.x, snap.pos.y, snap.pos.z}
}

pub fn (e EntityRef) teleport(pos world.Vec3) ! {
	mut w := e.world_
	applied := world_call[bool](mut w.runtime, fn [e, pos] (mut tx WorldTx) bool {
		mut target := tx.wr.entities.by_runtime_id(e.runtime_id) or { return false }
		target.pos = types.Vector3{pos.x, pos.y, pos.z}
		tx.wr.broadcast_world(target.move_packet())
		return true
	}) or { return error('world "${e.world_.name()}" is shutting down') }
	if !applied {
		return error('entity is no longer registered')
	}
}

pub fn (e EntityRef) damage(amount f32, fatal bool, source_runtime_id u64) ! {
	mut w := e.world_
	applied := world_call[bool](mut w.runtime, fn [e, amount, fatal, source_runtime_id] (mut tx WorldTx) bool {
		tx.wr.entities.by_runtime_id(e.runtime_id) or { return false }
		mut host := WorldEntityHost{
			wr: tx.wr
		}
		tx.wr.entities.damage(e.runtime_id, amount, fatal, mut host, source_runtime_id)
		return true
	}) or { return error('world "${e.world_.name()}" is shutting down') }
	if !applied {
		return error('entity is no longer registered')
	}
}

// close despawns the entity and tells viewers to drop it, the same path
// a normal death does.
pub fn (e EntityRef) close() ! {
	mut w := e.world_
	applied := world_call[bool](mut w.runtime, fn [e] (mut tx WorldTx) bool {
		tx.wr.entities.by_runtime_id(e.runtime_id) or { return false }
		tx.wr.entities.despawn(e.runtime_id)
		return true
	}) or { return error('world "${e.world_.name()}" is shutting down') }
	if !applied {
		return error('entity is no longer registered')
	}
}
