module entity

import protocol.types

// Actor is the shared identity of players and non-player entities rendered
// in a world. It allows world scoped queries to use one registry while each
// concrete type keeps its own movement and tick behavior.
//
// When narrowing an Actor to a concrete type, use the bare type name.
pub interface Actor {
	runtime_id() u64
	current_position() types.Vector3
	is_dead() bool
}

// ActorEntry is Manager's one storage unit.
struct ActorEntry {
	actor Actor
	epoch i64
}
