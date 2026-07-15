module entity

// Behaviour drives an Entity's per-tick logic, mirroring dragonfly's Behaviour
// interface. identifier() returns the network type id used when the entity is
// spawned for clients; tick() runs once per server tick before physics is
// applied. A Behaviour mutates the Entity directly (velocity, kill, etc.).
pub interface Behaviour {
	identifier() string
mut:
	tick(mut e Entity)
}

// PassiveBehaviour is a do-nothing behaviour for stationary/idle mobs. Physics
// still applies, so the entity falls to floor_y and rests there.
pub struct PassiveBehaviour {
	network_id string
}

pub fn (b &PassiveBehaviour) identifier() string {
	return b.network_id
}

pub fn (mut b PassiveBehaviour) tick(mut e Entity) {}

// ProjectileBehaviour flies with its initial velocity and despawns when it hits
// the ground or outlives max_age ticks - the shape of a snowball or egg.
pub struct ProjectileBehaviour {
	network_id string
	max_age    i64 = 100
}

pub fn (b &ProjectileBehaviour) identifier() string {
	return b.network_id
}

pub fn (mut b ProjectileBehaviour) tick(mut e Entity) {
	if e.age >= b.max_age || (e.on_ground && e.age > 1) {
		e.kill()
	}
}
