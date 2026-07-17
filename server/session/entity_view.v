module session

import protocol
import protocol.types

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

pub fn (mut h Hub) entity_position(runtime_id u64) ?types.Vector3 {
	if mut target := h.session_by_runtime(runtime_id) {
		return target.current_position()
	}
	e := h.entities.by_runtime_id(runtime_id) or { return none }
	return e.pos
}

pub fn (mut h Hub) entity_hit_test(pos types.Vector3, exclude_runtime_id u64) ?u64 {
	if rid := h.entities.hit_test(pos, exclude_runtime_id) {
		return rid
	}
	for mut target in h.snapshot() {
		if target.runtime_id == exclude_runtime_id {
			continue
		}
		tp := target.current_position()
		feet_y := tp.y - player_eye_height
		if pos.x >= tp.x - player_half_width && pos.x <= tp.x + player_half_width
			&& pos.z >= tp.z - player_half_width && pos.z <= tp.z + player_half_width
			&& pos.y >= feet_y && pos.y <= feet_y + player_height {
			return target.runtime_id
		}
	}
	return none
}

pub fn (mut h Hub) damage_entity(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3) {
	if mut target := h.session_by_runtime(runtime_id) {
		target.apply_knockback(knockback_from)
		target.take_damage(amount, source_name)
		return
	}
	h.entities.damage(runtime_id, amount, true, mut h, source_runtime_id)
}
