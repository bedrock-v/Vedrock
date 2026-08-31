module entity

import bedrock_v.protocol.types

// Dimensions describes an actor's collision box and related vertical
// offsets. Width and height are full dimensions.
//
// step_height is reserved for future auto step behavior and is not yet used
// by entity physics.
pub struct Dimensions {
pub:
	width         f32  = 0.6
	height        f32  = 1.8
	eye_height    f32  = 1.62
	step_height   f32  = 0.6
	has_collision bool = true
}

// Actor is the shared identity of players and non-player entities rendered
// in a world. It allows world scoped queries to use one registry while each
// concrete type keeps its own movement and tick behavior.
//
// When narrowing an Actor to a concrete type, use the bare type name.
pub interface Actor {
	runtime_id() u64
	current_position() types.Vector3
	// feet_position returns the bottom of the actor's collision box.
	// Use it for collision and hit testing because current_position may refer
	// to eye level for players but already represents feet for entities.
	feet_position() types.Vector3
	dimensions() Dimensions
	is_dead() bool
}

// ActorEntry is Manager's one storage unit.
struct ActorEntry {
	actor Actor
	epoch i64
}
