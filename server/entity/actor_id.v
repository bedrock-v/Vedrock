module entity

// ActorId names one actor for as long as it stays registered with one world.
//
// It replaces the (runtime_id, epoch) pair that used to be threaded through
// every signature and captured loose in every world_call closure. The epoch is
// the half that matters: a player who changes worlds keeps their runtime id but
// gets a new registration generation, so work started before the switch stops
// resolving instead of landing on whoever holds that id now.
//
// It is deliberately not a map key, V has no struct keys, so the registries
// stay keyed by value and check the epoch against what they stored.
pub struct ActorId {
pub:
	value u64
	epoch i64
}

// new_actor_id names the actor holding runtime_id in registration generation
// epoch.
pub fn new_actor_id(value u64, epoch i64) ActorId {
	return ActorId{
		value: value
		epoch: epoch
	}
}
