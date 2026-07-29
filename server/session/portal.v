module session

import protocol
import protocol.types
import server.world
import server.world.db

const portal_countdown_ticks = 80
const portal_cooldown_ticks = i64(30)
const portal_max_frame_size = 23
const portal_min_frame_w = 4
const portal_min_frame_h = 5

pub struct PortalOrientation {
pub:
	min_x       int
	min_y       int
	max_x       int
	max_y       int
	min_z       int
	max_z       int
	axis_z      bool
	const_coord int
}

pub struct PortalEntry {
pub:
	from_world_name string
	from_x          f32
	from_y          f32
	from_z          f32
pub mut:
	countdown_ticks int
	cooldown_ticks  int
}

pub struct PortalManager {
pub mut:
	tracked map[u64]PortalEntry
}

pub fn new_portal_manager() PortalManager {
	return PortalManager{
		tracked: map[u64]PortalEntry{}
	}
}

pub fn tick_portal(mut h Hub) {
	mut entering := []&NetworkSession{}
	for _, session in h.sessions {
		if session.runtime_id in h.portal.tracked || session.dead {
			continue
		}
		if is_player_in_portal(session.world_name(), session.position, &h) {
			entering << session
		}
	}
	for session in entering {
		h.portal.try_enter_portal(session)
	}
	if h.portal.tracked.len == 0 {
		return
	}

	mut to_remove := []u64{}
	mut to_teleport := []u64{}

	for runtime_id, mut entry in h.portal.tracked {
		if entry.cooldown_ticks > 0 {
			entry.cooldown_ticks--
			continue
		}
		session := h.session_by_runtime(runtime_id) or {
			to_remove << runtime_id
			continue
		}
		if session.dead || !is_player_in_portal(session.world_name(), session.position, &h) {
			to_remove << runtime_id
			continue
		}
		entry.countdown_ticks--
		if entry.countdown_ticks <= 0 {
			to_teleport << runtime_id
		}
	}

	for rid in to_remove {
		h.portal.tracked.delete(rid)
	}
	for rid in to_teleport {
		mut entry := h.portal.tracked[rid] or { continue }
		h.portal.tracked.delete(rid)
		do_teleport(rid, mut entry, mut h)
	}
}

fn is_player_in_portal(world_name string, pos types.Vector3, h &Hub) bool {
	wld := h.worlds[world_name] or { return false }
	bx := int(pos.x)
	by := int(pos.y)
	bz := int(pos.z)
	obsidian_id := world.obsidian.network_id
	air_id := world.air.network_id
	for dy := 0; dy <= 1; dy++ {
		id := wld.block_id(bx, by + dy, bz)
		if is_portal_id(id) {
			if portal_in_frame(bx, by + dy, bz, obsidian_id, air_id, wld) {
				return true
			}
			wld.set_block(bx, by + dy, bz, air_id)
		}
	}
	return false
}

fn portal_in_frame(x int, y int, z int, obsidian_id int, air_id int, wld &db.World) bool {
	has_edge_x := wld.block_id(x - 1, y, z) == obsidian_id
		|| wld.block_id(x + 1, y, z) == obsidian_id
		|| is_portal_id(wld.block_id(x - 1, y, z))
		|| is_portal_id(wld.block_id(x + 1, y, z))
	has_edge_z := wld.block_id(x, y, z - 1) == obsidian_id
		|| wld.block_id(x, y, z + 1) == obsidian_id
		|| is_portal_id(wld.block_id(x, y, z - 1))
		|| is_portal_id(wld.block_id(x, y, z + 1))
	if !has_edge_x && !has_edge_z {
		return false
	}

	mut has_top := false
	for dy := 1; dy <= 22; dy++ {
		id := wld.block_id(x, y + dy, z)
		if id == obsidian_id { has_top = true; break }
		if !is_portal_id(id) && id != air_id { break }
	}
	mut has_bottom := false
	for dy := 1; dy <= 22; dy++ {
		id := wld.block_id(x, y - dy, z)
		if id == obsidian_id { has_bottom = true; break }
		if !is_portal_id(id) && id != air_id { break }
	}
	return has_top && has_bottom
}

pub fn (mut m PortalManager) try_enter_portal(session &NetworkSession) bool {
	if session.runtime_id in m.tracked {
		return false
	}
	countdown := if session.game_mode == protocol.game_type_creative { 0 } else { portal_countdown_ticks }
	pos := session.position
	m.tracked[session.runtime_id] = PortalEntry{
		from_world_name: session.world_name()
		from_x:          pos.x
		from_y:          pos.y
		from_z:          pos.z
		countdown_ticks: countdown
		cooldown_ticks:  0
	}
	return true
}

fn do_teleport(runtime_id u64, mut entry PortalEntry, mut h Hub) {
	mut session := h.session_by_runtime(runtime_id) or { return }
	src_world := h.world(entry.from_world_name) or { return }
	src_dim := src_world.dimension
	target_dim, target_world_name := target_dimension_and_world(src_dim, h.default_world_name)

	if _ := h.world(target_world_name) {
	} else {
		h.load_world(target_world_name) or {
			h.create_world(target_world_name, target_dim, target_dim.default_generator) or {
				return
			}
		}
	}

	to_nether := src_dim.id == world.overworld.id
	dest_x, dest_y, dest_z := compute_portal_destination(int(entry.from_x), int(entry.from_y),
		int(entry.from_z), to_nether, target_dim)

	final_x, final_y, final_z := find_or_create_destination(target_world_name,
		dest_x, dest_y, dest_z, h)

	dim_name := if to_nether { 'the Nether' } else { 'the Overworld' }
	session.send_message('Entering ${dim_name}...') or {}
	// Spawn 2 blocks in front of the portal so the player isn't instantly
	// re-detected inside it and teleported back.
	session.teleport_to_world(target_world_name, f32(final_x) + 0.5, f32(final_y),
		f32(final_z) + 2.5)

	h.portal.tracked[session.runtime_id] = PortalEntry{
		from_world_name: target_world_name
		from_x:          f32(final_x)
		from_y:          f32(final_y)
		from_z:          f32(final_z)
		countdown_ticks: portal_countdown_ticks
		cooldown_ticks:  int(portal_cooldown_ticks)
	}
}

fn target_dimension_and_world(src_dim world.Dimension, overworld_name string) (world.Dimension, string) {
	if src_dim.id == world.overworld.id {
		return world.nether, 'nether'
	}
	return world.overworld, overworld_name
}

fn compute_portal_destination(x int, y int, z int, to_nether bool, dim world.Dimension) (int, int, int) {
	mut dx := x
	mut dz := z
	if to_nether {
		dx = x >> 3
		dz = z >> 3
	} else {
		dx = x << 3
		dz = z << 3
	}
	mut dy := y
	if dy < dim.min_y {
		dy = dim.min_y
	}
	if dy > dim.max_y() - 1 {
		dy = dim.max_y() - 1
	}
	return dx, dy, dz
}

fn find_or_create_destination(world_name string, dx int, dy int, dz int, h &Hub) (int, int, int) {
	wld := h.worlds[world_name] or { return dx, dy, dz }
	// Search radius scales with dimension. In the nether 1 block = 8 overworld,
	// so radius 128 overworld-blocks = 16 nether-blocks.
	search_radius := if wld.dimension.id == world.nether.id { 16 } else { 128 }
	// Find ground surface at the centre column to anchor the Y search.
	mut ground_y := dy
	for check_y := wld.dimension.max_y() - 1; check_y >= wld.dimension.min_y; check_y-- {
		bid := wld.block_id(dx, check_y, dz)
		if bid != world.air.network_id && !is_portal_id(bid) {
			ground_y = check_y
			break
		}
	}
	// Search ±16 Y around the surface and around dy, whichever is wider.
	mut min_y := if dy < ground_y { dy - 16 } else { ground_y - 16 }
	mut max_y := if dy > ground_y { dy + 16 } else { ground_y + 16 }
	if min_y < wld.dimension.min_y { min_y = wld.dimension.min_y }
	if max_y > wld.dimension.max_y() - 1 { max_y = wld.dimension.max_y() - 1 }
	for cy := max_y; cy >= min_y; cy-- {
		for cx := dx - search_radius; cx <= dx + search_radius; cx++ {
			for cz := dz - search_radius; cz <= dz + search_radius; cz++ {
				if is_portal_id(wld.block_id(cx, cy, cz)) {
					return cx, cy, cz
				}
			}
		}
	}
	return generate_portal_at(dx, dy, dz, wld)
}

fn generate_portal_at(dx int, dy int, dz int, wld &db.World) (int, int, int) {
	obsidian_id := world.obsidian.network_id
	portal_id := world.portal_block_z.network_id
	air_id := world.air.network_id

	const_x := dx
	mut base_y := dy

	// Scan up from min_y to find the surface ground — first solid block
	// with air above it. Scanning down from max_y hits the nether ceiling.
	for check_y := wld.dimension.min_y; check_y < wld.dimension.max_y() - portal_min_frame_h; check_y++ {
		bid := wld.block_id(const_x, check_y, dz)
		above := wld.block_id(const_x, check_y + 1, dz)
		if bid != air_id && bid != portal_id && (above == air_id || is_portal_id(above)) {
			base_y = check_y + 1
			break
		}
	}

	max_y := wld.dimension.max_y()
	if base_y + portal_min_frame_h > max_y {
		base_y = max_y - portal_min_frame_h
	}
	if base_y < wld.dimension.min_y {
		base_y = wld.dimension.min_y
	}

	frame_x := const_x
	frame_z_min := dz - 1
	frame_z_max := dz + 2

	if base_y < wld.dimension.min_y + 2 {
		for pz := frame_z_min - 1; pz <= frame_z_max + 1; pz++ {
			wld.set_block(frame_x, base_y - 1, pz, obsidian_id)
		}
	}

	// Flat frame — all blocks at the same X plane, like vanilla.
	for fy := base_y; fy < base_y + portal_min_frame_h; fy++ {
		wld.set_block(frame_x, fy, frame_z_min, obsidian_id)
		wld.set_block(frame_x, fy, frame_z_max, obsidian_id)
	}
	for fz := frame_z_min + 1; fz < frame_z_max; fz++ {
		wld.set_block(frame_x, base_y, fz, obsidian_id)
		wld.set_block(frame_x, base_y + portal_min_frame_h - 1, fz, obsidian_id)
	}

	interior_y := base_y + 1
	interior_y_max := base_y + portal_min_frame_h - 1
	for fz := frame_z_min + 1; fz < frame_z_max; fz++ {
		for fy := interior_y; fy < interior_y_max; fy++ {
			wld.set_block(frame_x, fy, fz, portal_id)
			wld.schedule_tick(frame_x, fy, fz, 1)
		}
	}

	center_z := (frame_z_min + frame_z_max) / 2
	return frame_x, interior_y, center_z
}

pub fn find_frame(x int, y int, z int, block_id fn (int, int, int) int) ?PortalOrientation {
	obsidian_id := world.obsidian.network_id
	air_id := world.air.network_id

	if block_id(x, y, z) != obsidian_id {
		return none
	}

	portal_id := world.portal_block.network_id
	is_interior := fn [air_id, portal_id, block_id](cx int, cy int, cz int) bool {
		id := block_id(cx, cy, cz)
		return id == air_id || id == portal_id
	}

	if is_interior(x, y + 1, z) {
		if o := find_frame_from_interior(x, y + 1, z, obsidian_id, air_id, block_id) {
			return o
		}
	}
	if is_interior(x, y - 1, z) {
		if o := find_frame_from_interior(x, y - 1, z, obsidian_id, air_id, block_id) {
			return o
		}
	}
	for dir in [[1, 0], [-1, 0], [0, 1], [0, -1]] {
		nx := x + dir[0]
		nz := z + dir[1]
		if is_interior(nx, y, nz) {
			if o := find_frame_from_interior(nx, y, nz, obsidian_id, air_id, block_id) {
				return o
			}
		}
	}
	for dy in [-1, 1] {
		for dir in [[1, 0], [-1, 0], [0, 1], [0, -1]] {
			nx := x + dir[0]
			nz := z + dir[1]
			if is_interior(nx, y + dy, nz) {
				if o := find_frame_from_interior(nx, y + dy, nz, obsidian_id, air_id, block_id) {
					return o
				}
			}
		}
	}
	return none
}

fn find_frame_from_interior(ix int, iy int, iz int, obsidian_id int, air_id int, block_id fn (int, int, int) int) ?PortalOrientation {
	portal_id := world.portal_block.network_id
	is_open := fn [air_id, portal_id, block_id](x int, y int, z int) bool {
		id := block_id(x, y, z)
		return id == air_id || id == portal_id
	}

	mut lx := ix
	for lx > ix - portal_max_frame_size {
		if block_id(lx - 1, iy, iz) == obsidian_id { break }
		if !is_open(lx - 1, iy, iz) { break }
		lx--
	}
	mut rx := ix
	for rx < ix + portal_max_frame_size {
		if block_id(rx + 1, iy, iz) == obsidian_id { break }
		if !is_open(rx + 1, iy, iz) { break }
		rx++
	}
	mut fz := iz
	for fz > iz - portal_max_frame_size {
		if block_id(ix, iy, fz - 1) == obsidian_id { break }
		if !is_open(ix, iy, fz - 1) { break }
		fz--
	}
	mut bz := iz
	for bz < iz + portal_max_frame_size {
		if block_id(ix, iy, bz + 1) == obsidian_id { break }
		if !is_open(ix, iy, bz + 1) { break }
		bz++
	}
	mut dy := iy
	for dy > world.nether.min_y {
		if block_id(ix, dy - 1, iz) == obsidian_id { break }
		if !is_open(ix, dy - 1, iz) { break }
		dy--
	}
	mut uy := iy
	for uy < world.overworld.max_y() {
		if block_id(ix, uy + 1, iz) == obsidian_id { break }
		if !is_open(ix, uy + 1, iz) { break }
		uy++
	}

	found_x := (lx > ix - portal_max_frame_size && block_id(lx - 1, iy, iz) == obsidian_id)
		|| (rx < ix + portal_max_frame_size && block_id(rx + 1, iy, iz) == obsidian_id)
	found_z := (fz > iz - portal_max_frame_size && block_id(ix, iy, fz - 1) == obsidian_id)
		|| (bz < iz + portal_max_frame_size && block_id(ix, iy, bz + 1) == obsidian_id)

	if !found_x && !found_z {
		return none
	}
	if block_id(ix, dy - 1, iz) != obsidian_id || block_id(ix, uy + 1, iz) != obsidian_id {
		return none
	}

	if found_z {
		frame_min_z := fz - 1
		frame_max_z := bz + 1
		frame_min_y := dy - 1
		frame_max_y := uy + 1
		frame_min_x := ix - 1
		frame_max_x := ix + 1
		if frame_max_z - frame_min_z + 1 < portal_min_frame_w
			|| frame_max_z - frame_min_z + 1 > portal_max_frame_size { return none }
		if frame_max_y - frame_min_y + 1 < portal_min_frame_h
			|| frame_max_y - frame_min_y + 1 > portal_max_frame_size { return none }
		if !validate_flat_frame(frame_min_x, frame_max_x, frame_min_y, frame_max_y,
			frame_min_z, frame_max_z, true, obsidian_id, block_id) {
			return none
		}
		return PortalOrientation{
			min_x: frame_min_x, max_x: frame_max_x,
			min_y: frame_min_y, max_y: frame_max_y,
			min_z: frame_min_z, max_z: frame_max_z,
			axis_z: true, const_coord: ix
		}
	}
	frame_min_x := lx - 1
	frame_max_x := rx + 1
	frame_min_y := dy - 1
	frame_max_y := uy + 1
	frame_min_z := iz - 1
	frame_max_z := iz + 1
	if frame_max_x - frame_min_x + 1 < portal_min_frame_w
		|| frame_max_x - frame_min_x + 1 > portal_max_frame_size { return none }
	if frame_max_y - frame_min_y + 1 < portal_min_frame_h
		|| frame_max_y - frame_min_y + 1 > portal_max_frame_size { return none }
	if !validate_flat_frame(frame_min_x, frame_max_x, frame_min_y, frame_max_y,
		frame_min_z, frame_max_z, false, obsidian_id, block_id) {
		return none
	}
	return PortalOrientation{
		min_x: frame_min_x, max_x: frame_max_x,
		min_y: frame_min_y, max_y: frame_max_y,
		min_z: frame_min_z, max_z: frame_max_z,
		axis_z: false, const_coord: iz
	}
}

fn validate_flat_frame(min_x int, max_x int, min_y int, max_y int, min_z int, max_z int, axis_z bool, obsidian_id int, block_id fn (int, int, int) int) bool {
	if axis_z {
		mid_x := (min_x + max_x) / 2
		for cz := min_z + 1; cz < max_z; cz++ {
			if block_id(mid_x, min_y, cz) != obsidian_id { return false }
			if block_id(mid_x, max_y, cz) != obsidian_id { return false }
		}
		for cy := min_y + 1; cy < max_y; cy++ {
			if block_id(mid_x, cy, min_z) != obsidian_id { return false }
			if block_id(mid_x, cy, max_z) != obsidian_id { return false }
		}
		return true
	}
	mid_z := (min_z + max_z) / 2
	for cx := min_x + 1; cx < max_x; cx++ {
		if block_id(cx, min_y, mid_z) != obsidian_id { return false }
		if block_id(cx, max_y, mid_z) != obsidian_id { return false }
	}
	for cy := min_y + 1; cy < max_y; cy++ {
		if block_id(min_x, cy, mid_z) != obsidian_id { return false }
		if block_id(max_x, cy, mid_z) != obsidian_id { return false }
	}
	return true
}

fn is_portal_id(id int) bool {
	return id == world.portal_block.network_id
		|| id == world.portal_block_x.network_id
		|| id == world.portal_block_z.network_id
}
