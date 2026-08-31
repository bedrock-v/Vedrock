module session

import bedrock_v.protocol.types

// nearest_player_name is the display-name-facing form of nearest_player. It
// resolves the runtime id back to a name rather than leaking the internal
// runtime id concept into a public facing result.
fn (mut h Hub) nearest_player_name(x f32, y f32, z f32, radius f32) ?string {
	nearest := h.find_nearest_player(types.Vector3{x, y, z}, radius) or { return none }
	target := h.session_by_runtime(nearest.runtime_id) or { return none }
	return target.name()
}

// NearestPlayer is the closest connected session to a point, found by
// find_nearest_player.
struct NearestPlayer {
	runtime_id u64
	pos        types.Vector3
}

// find_nearest_player scans every connected session (across all worlds) for
// the closest one to pos within radius or none if nobody is in range.
fn (mut h Hub) find_nearest_player(pos types.Vector3, radius f32) ?NearestPlayer {
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
	if !found {
		return none
	}
	return NearestPlayer{best_rid, best_pos}
}
