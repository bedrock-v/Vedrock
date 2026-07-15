module session

import protocol

// broadcast_near delivers p only to players whose position is within radius of
// the point (x, y, z). Used by the entity Manager for view-distance culling so
// spawn and move packets never reach players too far away to render the entity.
// Distance is compared squared to skip the sqrt.
pub fn (mut h Hub) broadcast_near(x f32, y f32, z f32, radius f32, p protocol.Packet) {
	r2 := radius * radius
	for mut target in h.snapshot() {
		// Read the position under the target's own pos_mutex - it is written on
		// that session's thread while we read here on the actor thread.
		pos := target.current_position()
		dx := pos.x - x
		dy := pos.y - y
		dz := pos.z - z
		if dx * dx + dy * dy + dz * dz <= r2 {
			target.deliver(p)
		}
	}
}
