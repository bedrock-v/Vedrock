module entity

import math
import rand

// Behaviour drives an Entity's per-tick logic, mirroring dragonfly's Behaviour
// interface. identifier() returns the network type id used when the entity is
// spawned for clients; tick() runs once per server tick before physics is
// applied, with Host access for querying/affecting the rest of the world. A
// Behaviour mutates the Entity directly (velocity, kill, etc.).
pub interface Behaviour {
	identifier() string
mut:
	tick(mut e Entity, mut host Host)
}

// HurtBehaviour is an opt-in capability: a Behaviour implementing it is
// notified whenever its Entity survives a hit, letting e.g. a hostile mob
// start targeting whoever hit it.
pub interface HurtBehaviour {
mut:
	on_hurt(mut e Entity, amount f32, source_runtime_id u64)
}

// DeathBehaviour is an opt-in capability notified once, right before an
// Entity that died from Entity.hurt is despawned , as opposed to
// Behaviour.tick calling kill() directly for other reasons (a projectile
// expiring, a wandering mob walking into the void).
pub interface DeathBehaviour {
mut:
	on_death(mut e Entity)
}

const wander_interval_ticks = i64(100)
const wander_speed = f32(0.08)
const hostile_speed = f32(0.14)

// set_wander_velocity picks a new random horizontal direction and walk speed.
fn set_wander_velocity(mut e Entity, speed f32) {
	angle := rand.f32_in_range(0, f32(2.0 * math.pi)) or { 0 }
	e.velocity.x = math.cosf(angle) * speed
	e.velocity.z = math.sinf(angle) * speed
	e.yaw = angle * (180.0 / f32(math.pi))
	e.head_yaw = e.yaw
}

// PassiveBehaviour wanders in a new random direction roughly every
// wander_interval_ticks while grounded and otherwise does nothing.
// Physics still applies, so the entity falls to floor_y and
// rests there between wanders.
@[heap]
pub struct PassiveBehaviour {
	network_id string
mut:
	wander_cooldown i64 = wander_interval_ticks
}

pub fn (b &PassiveBehaviour) identifier() string {
	return b.network_id
}

pub fn (mut b PassiveBehaviour) tick(mut e Entity, mut host Host) {
	if !e.on_ground {
		return
	}
	b.wander_cooldown--
	if b.wander_cooldown > 0 {
		return
	}
	b.wander_cooldown = wander_interval_ticks
	set_wander_velocity(mut e, wander_speed)
}

// HostileBehaviour wanders the same way PassiveBehaviour does until
// on_hurt gives it a target, then chases that runtime id directly.
@[heap]
pub struct HostileBehaviour {
	network_id string
mut:
	wander_cooldown   i64 = wander_interval_ticks
	target_runtime_id u64
	has_target        bool
}

pub fn (b &HostileBehaviour) identifier() string {
	return b.network_id
}

pub fn (mut b HostileBehaviour) tick(mut e Entity, mut host Host) {
	if b.has_target {
		if target_pos := host.entity_position(b.target_runtime_id) {
			dx := target_pos.x - e.pos.x
			dz := target_pos.z - e.pos.z
			dist := math.sqrtf(dx * dx + dz * dz)
			if dist > 0.2 {
				e.velocity.x = (dx / dist) * hostile_speed
				e.velocity.z = (dz / dist) * hostile_speed
				e.yaw = f32(math.atan2(f64(dz), f64(dx)) * (180.0 / math.pi))
				e.head_yaw = e.yaw
			}
			return
		}
		// target no longer exists (died, despawned); go back to wandering.
		b.has_target = false
	}
	if !e.on_ground {
		return
	}
	b.wander_cooldown--
	if b.wander_cooldown > 0 {
		return
	}
	b.wander_cooldown = wander_interval_ticks
	set_wander_velocity(mut e, wander_speed)
}

// on_hurt makes the mob start chasing whoever/whatever just hit it. Plain
// PassiveBehaviour mobs don't implement HurtBehaviour, so being attacked
// never gives them a target.
pub fn (mut b HostileBehaviour) on_hurt(mut e Entity, amount f32, source_runtime_id u64) {
	if source_runtime_id == 0 {
		return
	}
	b.has_target = true
	b.target_runtime_id = source_runtime_id
}

// ProjectileBehaviour flies with its initial velocity, despawns when it hits
// the ground or outlives max_age ticks and deals damage to the first entity or player its path
// touches.
@[heap]
pub struct ProjectileBehaviour {
	network_id string
	max_age    i64 = 100
	damage     f32
}

pub fn (b &ProjectileBehaviour) identifier() string {
	return b.network_id
}

pub fn (mut b ProjectileBehaviour) tick(mut e Entity, mut host Host) {
	if e.age >= b.max_age || (e.on_ground && e.age > 1) {
		e.kill()
		return
	}
	if e.age <= 1 {
		return
	}
	if hit_runtime_id := host.entity_hit_test(e.pos, e.runtime_id) {
		host.damage_entity(hit_runtime_id, b.damage, e.identifier, e.runtime_id, e.pos)
		e.kill()
	}
}
