module world

pub struct NeighborBlockIDs {
pub:
	north int
	east  int
	south int
	west  int
	above int
	below int
}

pub struct DoorPlacement {
pub:
	lower int
	upper int
}

pub struct DoorToggle {
pub:
	clicked int
	pair    int
}

pub fn is_door_name(name string) bool {
	return name.ends_with('_door') || name == 'minecraft:wooden_door'
		|| name == 'minecraft:iron_door'
}

pub fn is_trapdoor_name(name string) bool {
	return name.ends_with('_trapdoor') || name == 'minecraft:trapdoor'
}

pub fn is_fence_gate_name(name string) bool {
	return name.ends_with('_fence_gate') || name == 'minecraft:fence_gate'
}

pub fn (p &BlockPalette) toggled_open(id int) ?int {
	v := p.variant(id) or { return none }
	open := v.states['open_bit'] or { return none }
	next := if open == '1' || open == 'true' { '0' } else { '1' }
	return p.with_state(id, 'open_bit', next)
}

pub fn (p &BlockPalette) door_pair_id(id int) ?int {
	v := p.variant(id) or { return none }
	if !is_door_name(v.name) {
		return none
	}
	upper := v.states['upper_block_bit'] or { return none }
	next := if upper == '1' || upper == 'true' { '0' } else { '1' }
	return p.with_state(id, 'upper_block_bit', next)
}

pub fn (p &BlockPalette) door_toggled_pair(clicked_id int, pair_id int) ?DoorToggle {
	clicked := p.variant(clicked_id) or { return none }
	pair := p.variant(pair_id) or { return none }
	if !is_door_name(clicked.name) || clicked.name != pair.name {
		return none
	}
	clicked_top := state_bool(clicked.states, 'upper_block_bit', false)
	pair_top := state_bool(pair.states, 'upper_block_bit', false)
	if clicked_top == pair_top {
		return none
	}
	clicked_open := state_bool(clicked.states, 'open_bit', false)
	next_open := if clicked_open { '0' } else { '1' }
	return DoorToggle{
		clicked: p.with_state(clicked_id, 'open_bit', next_open) or { return none }
		pair:    p.with_state(pair_id, 'open_bit', next_open) or { return none }
	}
}

pub fn (p &BlockPalette) is_door_top(id int) bool {
	v := p.variant(id) or { return false }
	return is_door_name(v.name) && state_bool(v.states, 'upper_block_bit', false)
}

pub fn (p &BlockPalette) door_placement(id int, yaw f32, neighbors NeighborBlockIDs) ?DoorPlacement {
	v := p.variant(id) or { return none }
	if !is_door_name(v.name) || 'upper_block_bit' !in v.states {
		return none
	}
	mut lower := p.oriented(id, yaw, 1, 0.5)
	lower = p.with_state(lower, 'upper_block_bit', '0') or { lower }
	lower = p.with_state(lower, 'open_bit', '0') or { lower }
	lower = p.with_state(lower, 'door_hinge_bit', p.door_hinge(lower, neighbors).str()) or { lower }
	upper := p.with_state(lower, 'upper_block_bit', '1') or { return none }
	return DoorPlacement{
		lower: lower
		upper: upper
	}
}

pub fn (p &BlockPalette) connected_block(id int, neighbors NeighborBlockIDs) int {
	v := p.variant(id) or { return id }
	if v.name.ends_with('_wall') {
		return p.connected_wall(id, neighbors)
	}
	if is_fence_gate_name(v.name) {
		return p.fence_gate_in_wall(id, neighbors)
	}
	return id
}

pub fn (p &BlockPalette) merged_slab(existing_id int, placing_id int, click_face int, click_y f32, clicked bool) ?int {
	existing := p.variant(existing_id) or { return none }
	placing := p.variant(placing_id) or { return none }
	if !is_single_slab_name(existing.name) || !is_single_slab_name(placing.name) {
		return none
	}
	if slab_family_name(existing.name) != slab_family_name(placing.name) {
		return none
	}
	existing_top := slab_is_top(existing.states)
	if clicked {
		if existing_top {
			if click_face != 0 && click_y > 0.5 {
				return none
			}
		} else {
			if click_face != 1 && click_y < 0.5 {
				return none
			}
		}
	}
	double_name := double_slab_name(existing.name)
	return p.by_key[palette_key(double_name, {
		'minecraft:vertical_half': if existing_top { 'top' } else { 'bottom' }
	})] or { return none }
}

fn (p &BlockPalette) door_hinge(lower_id int, neighbors NeighborBlockIDs) int {
	v := p.variant(lower_id) or { return 0 }
	face := door_facing_face(v.states)
	left := rotate_left_face(face)
	right := rotate_right_face(face)
	left_solid := p.neighbor_solid(neighbors, left)
	right_solid := p.neighbor_solid(neighbors, right)
	if left_solid && !right_solid {
		return 1
	}
	return 0
}

fn (p &BlockPalette) connected_wall(id int, neighbors NeighborBlockIDs) int {
	mut out := id
	north := if p.connects_wall_to(neighbors.north, 2) { 'short' } else { 'none' }
	east := if p.connects_wall_to(neighbors.east, 5) { 'short' } else { 'none' }
	south := if p.connects_wall_to(neighbors.south, 3) { 'short' } else { 'none' }
	west := if p.connects_wall_to(neighbors.west, 4) { 'short' } else { 'none' }
	post := wall_post(north, east, south, west)
	out = p.with_state(out, 'wall_connection_type_north', north) or { out }
	out = p.with_state(out, 'wall_connection_type_east', east) or { out }
	out = p.with_state(out, 'wall_connection_type_south', south) or { out }
	out = p.with_state(out, 'wall_connection_type_west', west) or { out }
	out = p.with_state(out, 'wall_post_bit', if post { '1' } else { '0' }) or { out }
	return out
}

fn wall_post(north string, east string, south string, west string) bool {
	n := north != 'none'
	e := east != 'none'
	s := south != 'none'
	w := west != 'none'
	count := int(n) + int(e) + int(s) + int(w)
	if count < 2 {
		return true
	}
	if n && s && !e && !w {
		return false
	}
	if e && w && !n && !s {
		return false
	}
	return true
}

fn (p &BlockPalette) fence_gate_in_wall(id int, neighbors NeighborBlockIDs) int {
	v := p.variant(id) or { return id }
	face := cardinal_face(state_string(v.states, 'minecraft:cardinal_direction', 'south'))
	in_wall := if face == 2 || face == 3 {
		p.is_wall(neighbors.east) || p.is_wall(neighbors.west)
	} else {
		p.is_wall(neighbors.north) || p.is_wall(neighbors.south)
	}
	return p.with_state(id, 'in_wall_bit', if in_wall { '1' } else { '0' }) or { id }
}

fn (p &BlockPalette) connects_wall_to(id int, face int) bool {
	v := p.variant(id) or { return false }
	m := p.model(id)
	if m.kind == .wall || m.kind == .thin {
		return true
	}
	if is_fence_gate_name(v.name) {
		gate_face := cardinal_face(state_string(v.states, 'minecraft:cardinal_direction', 'south'))
		return face_axis(gate_face) != face_axis(face)
	}
	return m.face_solid(face_opposite(face))
}

fn (p &BlockPalette) neighbor_solid(neighbors NeighborBlockIDs, face int) bool {
	id := match face {
		2 { neighbors.north }
		3 { neighbors.south }
		4 { neighbors.west }
		5 { neighbors.east }
		else { air.network_id }
	}

	if id == air.network_id {
		return false
	}
	_ := p.variant(id) or { return false }
	return p.model(id).face_solid(face_opposite(face))
}

fn (p &BlockPalette) is_wall(id int) bool {
	v := p.variant(id) or { return false }
	return v.name.ends_with('_wall')
}

fn is_single_slab_name(name string) bool {
	return name.ends_with('_slab') && !name.contains('double_slab')
}

fn slab_family_name(name string) string {
	return name.replace('_slab', '')
}

fn double_slab_name(name string) string {
	return name.replace('_slab', '_double_slab')
}

fn face_axis(face int) int {
	return match face {
		2, 3 { 2 }
		4, 5 { 0 }
		else { 1 }
	}
}
