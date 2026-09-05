module entity

import math
import bedrock_v.protocol.types

const orb_gravity = f32(0.03)
const orb_drag = f32(0.02)

// orb_pickup_delay_ticks keeps an orb on the ground briefly, so the player who
// dropped it on death does not immediately walk back into it.
pub const orb_pickup_delay_ticks = i64(10)

pub const orb_existence_duration_ticks = i64(6000)

// orb_attract_radius is how far an orb notices a player and starts drifting
// towards them; orb_pickup_radius is how close it has to get to be collected.
const orb_attract_radius = f32(6.0)
const orb_pickup_radius = f32(1.0)
const orb_attract_speed = f32(0.12)

// orb_max_value is the largest amount one orb carries. A bigger award is split
// across several, the way vanilla splits it.
pub const orb_max_value = 11

fn orb_dimensions() Dimensions {
	return Dimensions{
		width:         0.25
		height:        0.25
		eye_height:    0.125
		step_height:   0.0
		has_collision: true
	}
}

// ExperienceOrbBehaviour is a dropped lump of experience. It falls, drifts
// towards a player who comes near, and is gone the moment it is collected.
@[heap]
pub struct ExperienceOrbBehaviour {
pub mut:
	value              int = 1
	pickup_delay_ticks i64 = orb_pickup_delay_ticks
}

pub fn new_experience_orb_behaviour(value int, pickup_delay_ticks i64) &ExperienceOrbBehaviour {
	return &ExperienceOrbBehaviour{
		value:              value
		pickup_delay_ticks: pickup_delay_ticks
	}
}

pub fn (b &ExperienceOrbBehaviour) identifier() string {
	return 'minecraft:xp_orb'
}

pub fn (b &ExperienceOrbBehaviour) dimensions() Dimensions {
	return orb_dimensions()
}

pub fn (b &ExperienceOrbBehaviour) despawn_policy() DespawnPolicy {
	return DespawnPolicy{}
}

pub fn (b &ExperienceOrbBehaviour) takes_fall_damage() bool {
	return false
}

pub fn (mut b ExperienceOrbBehaviour) tick(mut e Entity, mut host Host) {
	e.gravity_accel = orb_gravity
	e.drag_factor = orb_drag

	if b.value <= 0 || e.age >= orb_existence_duration_ticks {
		e.kill()
		return
	}
	if e.age < b.pickup_delay_ticks {
		return
	}
	target_rid := host.nearest_player(e.pos, orb_attract_radius) or { return }
	target_pos := host.entity_position(target_rid) or { return }
	if within_pickup_range(e.pos, target_pos) {
		if !host.grant_experience(target_rid, b.value) {
			return
		}
		host.notify_item_taken(e.runtime_id, target_rid)
		e.kill()
		return
	}
	drift_towards(mut e, target_pos)
}

// split_experience breaks an award into the orbs it is dropped as, largest
// first, so a big award is not one impossible-to-miss lump.
pub fn split_experience(amount int) []int {
	mut out := []int{}
	mut remaining := amount
	for remaining > 0 {
		value := if remaining > orb_max_value { orb_max_value } else { remaining }
		out << value
		remaining -= value
	}
	return out
}

fn within_pickup_range(pos types.Vector3, target types.Vector3) bool {
	dx := target.x - pos.x
	dy := target.y - pos.y
	dz := target.z - pos.z
	return dx * dx + dy * dy + dz * dz <= orb_pickup_radius * orb_pickup_radius
}

fn drift_towards(mut e Entity, target types.Vector3) {
	dx := target.x - e.pos.x
	dy := target.y - e.pos.y
	dz := target.z - e.pos.z
	distance := math.sqrtf(dx * dx + dy * dy + dz * dz)
	if distance <= 0 {
		return
	}
	e.velocity.x = dx / distance * orb_attract_speed
	e.velocity.y = dy / distance * orb_attract_speed
	e.velocity.z = dz / distance * orb_attract_speed
}
