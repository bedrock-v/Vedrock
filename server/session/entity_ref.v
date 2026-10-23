module session

import bedrock_v.protocol.types
import server.worldrt

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
	found := worldrt.world_call[bool]('EntityRef.lookup', mut w.runtime, fn [runtime_id] (mut tx worldrt.WorldTx) bool {
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
	return worldrt.world_call[bool]('EntityRef.valid', mut w.runtime, fn [e] (mut tx worldrt.WorldTx) bool {
		tx.wr.entities.by_runtime_id(e.runtime_id) or { return false }
		return true
	}) or { false }
}

// position is the entity's current position. Fails if the entity has
// despawned or its world is shutting down.
pub fn (e EntityRef) position() !types.Vector3 {
	mut w := e.world_
	snap := worldrt.world_call[EntityRefSnapshot]('EntityRef.position', mut w.runtime, fn [e] (mut tx worldrt.WorldTx) EntityRefSnapshot {
		target := tx.wr.entities.by_runtime_id(e.runtime_id) or { return EntityRefSnapshot{} }
		return EntityRefSnapshot{
			found: true
			pos:   target.pos
		}
	}) or { return error('world "${e.world_.name()}" is shutting down') }
	if !snap.found {
		return error('entity is no longer registered')
	}
	return snap.pos
}

// teleport moves the entity within its world and broadcasts the move to
// observers. Same failure mode as position.
pub fn (e EntityRef) teleport(pos types.Vector3) ! {
	mut w := e.world_
	applied := worldrt.world_call[bool]('EntityRef.teleport', mut w.runtime, fn [e, pos] (mut tx worldrt.WorldTx) bool {
		mut target := tx.wr.entities.by_runtime_id(e.runtime_id) or { return false }
		target.pos = pos
		for mut v in tx.wr.viewers() {
			v.view_entity_movement(target)
		}
		return true
	}) or { return error('world "${e.world_.name()}" is shutting down') }
	if !applied {
		return error('entity is no longer registered')
	}
}

// AttackerRef identifies who or what dealt damage to an entity.
// A player, another entity or (via none) nothing attributable, e.g. environmental
// damage. EntityRef.damage takes this instead of a raw runtime id so a
// caller never needs to know entities and players share an id space
// internally.
pub type AttackerRef = EntityRef | PlayerRef

fn (a AttackerRef) runtime_id() u64 {
	return match a {
		EntityRef { a.runtime_id }
		PlayerRef { a.id.value }
	}
}

// damage hurts the entity by amount, killing it outright if fatal is true
// (otherwise normal health/death rules apply). source attributes the hit
// for mob-targeting purposes (see AttackerRef); pass none for damage with
// no attacker. Same failure mode as position.
pub fn (e EntityRef) damage(amount f32, fatal bool, source ?AttackerRef) ! {
	source_runtime_id := if s := source { s.runtime_id() } else { u64(0) }
	mut w := e.world_
	applied := worldrt.world_call[bool]('EntityRef.damage', mut w.runtime, fn [e, amount, fatal, source_runtime_id] (mut tx worldrt.WorldTx) bool {
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
	applied := worldrt.world_call[bool]('EntityRef.close', mut w.runtime, fn [e] (mut tx worldrt.WorldTx) bool {
		tx.wr.entities.by_runtime_id(e.runtime_id) or { return false }
		tx.wr.entities.despawn(e.runtime_id)
		return true
	}) or { return error('world "${e.world_.name()}" is shutting down') }
	if !applied {
		return error('entity is no longer registered')
	}
}
