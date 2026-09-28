module world

// Entity is anything a world can hold. A world reaches one only through a
// transaction. Every method here runs on that world's own thread.
pub interface Entity {
	id() u64
}

// Handle is an entity's identity. It holds the entity's state whether or not a
// world holds the entity and becomes a live entity inside a transaction on the
// world holding it.
//
// `entity` and `world` are private to this package: a handle gives a caller an
// identity, not access.
@[heap]
pub struct Handle {
mut:
	id_ u64
	// world is the runtime holding the entity or nil between being removed
	// from one world and added to the next.
	world  &Runtime = unsafe { nil }
	entity Entity
}

// new_handle wraps an entity that is in no world yet. Add it to one with Tx.add
// before anything can reach it.
pub fn new_handle(id u64, entity Entity) &Handle {
	return &Handle{
		id_:    id
		world:  unsafe { nil }
		entity: entity
	}
}

// id names the entity. It never changes, so it can be read without a
// transaction.
pub fn (h &Handle) id() u64 {
	return h.id_
}

// Ref is a typed reference to an entity and what a caller keeps. It follows
// the entity: work scheduled through it runs on whichever world holds the
// entity at the time.
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

// get returns the entity and only inside a transaction on the world holding
// it. The pointer is to the world's own copy. Changing it changes the
// world's state.
//
// It fails if another world holds the entity, no world holds it, or it is not
// of type T.
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
