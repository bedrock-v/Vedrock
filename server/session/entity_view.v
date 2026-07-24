module session

import protocol.types

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

// find_nearest_player scans every connected session (across all worlds) for
// the closest one to pos within radius, returning its runtime id, position
// and whether anyone was found.
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
