module session

import protocol
import protocol.types
import server.event

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
		target.apply_knockback(knockback_from, knockback_horizontal, knockback_vertical)
		target.take_damage(amount, source_name)
		return
	}
	h.entities.damage(runtime_id, amount, true, mut h, source_runtime_id)
}

pub fn (mut h Hub) nearest_player(pos types.Vector3, radius f32) ?u64 {
	rid, _, found := h.find_nearest_player(pos, radius)
	if !found {
		return none
	}
	return rid
}

// notify_entity_despawn dispatches EntityDespawnData. Observational only,
// so cancellation isn't checked here.
pub fn (mut h Hub) notify_entity_despawn(identifier string, x f32, y f32, z f32) {
	mut ctx := event.new_context(event.EntityDespawnData{
		identifier: identifier
		x:          x
		y:          y
		z:          z
	})
	h.events.entity_despawn(mut ctx)
}

// nearest_player_name is the plugin.ServerView facing form of nearest_player.
// It resolves the runtime id back to a display name rather than leaking the
// internal runtime id concept into the plugin surface.
pub fn (mut h Hub) nearest_player_name(x f32, y f32, z f32, radius f32) ?string {
	rid, _, found := h.find_nearest_player(types.Vector3{x, y, z}, radius)
	if !found {
		return none
	}
	target := h.session_by_runtime(rid) or { return none }
	return target.name()
}

// find_nearest_player scans live sessions for the closest one to pos within
// radius, returning its runtime id, position and whether anyone was found.
// Shared by entity.Host's nearest_player (proactive mob targeting) and
// plugin.ServerView's nearest_player_name.
fn (mut h Hub) find_nearest_player(pos types.Vector3, radius f32) (u64, types.Vector3, bool) {
	mut best_rid := u64(0)
	mut best_pos := types.Vector3{}
	mut best_dist_sq := radius * radius
	mut found := false
	for mut target in h.snapshot() {
		tp := target.current_position()
		dx := tp.x - pos.x
		dy := tp.y - pos.y
		dz := tp.z - pos.z
		dist_sq := dx * dx + dy * dy + dz * dz
		if dist_sq <= best_dist_sq {
			best_rid = target.runtime_id
			best_pos = tp
			best_dist_sq = dist_sq
			found = true
		}
	}
	return best_rid, best_pos, found
}
