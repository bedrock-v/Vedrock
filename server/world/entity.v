module world

// Entity is anything a world can hold. A world reaches one only through a
// transaction. Every method here runs on that world's own thread.
pub interface Entity {
	id() u64
}

// Handle is an entity's identity. It outlives the entity's membership of any
// one world: it holds the entity's state whether the entity is in a world or
// not and turns back into a live entity only inside a transaction on whichever
// world holds it now.
//
// Nothing outside this package may read `entity` or `world`. A caller that has
// a handle has an identity, not access.
pub struct Handle {
mut:
	id_ u64
	// world is the runtime holding the entity or nil while it is held by
	// nobody, between being removed from one world and added to the next.
	world  &Runtime = unsafe { nil }
	entity Entity
}

// new_handle takes an entity out of any world's hands. Add it to a world with
// Tx.add before anything can reach it.
pub fn new_handle(id u64, entity Entity) &Handle {
	return &Handle{
		id_:    id
		world:  unsafe { nil }
		entity: entity
	}
}

// id is the entity's identity, readable without a transaction because it never
// changes and names the entity rather than exposing it.
pub fn (h &Handle) id() u64 {
	return h.id_
}

// Ref is a typed reference to an entity and the durable thing a caller keeps.
// It follows the entity: work scheduled through it runs on whichever world
// holds the entity when the work runs.
//
// Every field is set here rather than through struct defaults: a specialized
// generic struct loses its defaults wherever it is used as a field of something
// else. Check: https://github.com/vlang/v/pull/28723 & https://github.com/vlang/v/pull/28571
pub struct Ref[T] {
	handle &Handle
}

// ref builds a typed reference to the entity a handle names.
pub fn ref[T](h &Handle) Ref[T] {
	return Ref[T]{
		handle: h
	}
}

// id is the referenced entity's identity.
pub fn (r Ref[T]) id() u64 {
	return r.handle.id_
}

// get is the entity itself and only inside a transaction on the world that
// holds it. What comes back points at the entity the world holds. Changing
// it changes the world's own state, which is why it is reachable here and
// nowhere else. It fails when the entity is held by another world, is held by
// none, or is not of type T.
pub fn (r Ref[T]) get(tx &Tx) ?&T {
	tx.ensure_live()
	if isnil(r.handle.world) || r.handle.world != tx.world {
		return none
	}
	e := r.handle.entity
	if e is T {
		return e
	}
	return none
}
