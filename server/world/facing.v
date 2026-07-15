module world

// Facing is a canonical block direction, independent of the many per-block
// state encodings (cardinal_direction string, weirdo_direction int, ...).
pub enum Facing {
	down
	up
	north
	south
	east
	west
}

// look_facing maps a player yaw (degrees) to the horizontal direction the
// player is looking. Bedrock yaw: 0 = south, 90 = west, 180 = north, 270 = east.
pub fn look_facing(yaw f32) Facing {
	mut y := yaw - (f32(int(yaw / 360.0)) * 360.0)
	if y < 0 {
		y += 360.0
	}
	return match true {
		y >= 45.0 && y < 135.0 { Facing.west }
		y >= 135.0 && y < 225.0 { Facing.north }
		y >= 225.0 && y < 315.0 { Facing.east }
		else { Facing.south }
	}
}

fn opposite(f Facing) Facing {
	return match f {
		.down { Facing.up }
		.up { Facing.down }
		.north { Facing.south }
		.south { Facing.north }
		.east { Facing.west }
		.west { Facing.east }
	}
}

fn cardinal_string(f Facing) string {
	return match f {
		.north { 'north' }
		.south { 'south' }
		.east { 'east' }
		.west { 'west' }
		else { 'south' }
	}
}

// weirdo_direction (stairs): 0 = east, 1 = west, 2 = south, 3 = north.
fn weirdo_value(f Facing) int {
	return match f {
		.east { 0 }
		.west { 1 }
		.south { 2 }
		.north { 3 }
		else { 0 }
	}
}

// facing_direction: 0 = down, 1 = up, 2 = north, 3 = south, 4 = west, 5 = east.
fn facing_direction_value(f Facing) int {
	return match f {
		.down { 0 }
		.up { 1 }
		.north { 2 }
		.south { 3 }
		.west { 4 }
		.east { 5 }
	}
}

// pillar_axis from the clicked block face: top/bottom -> y, north/south -> z,
// west/east -> x.
fn axis_from_face(face int) string {
	return match face {
		0, 1 { 'y' }
		2, 3 { 'z' }
		else { 'x' }
	}
}

// oriented returns the network id the given block should be placed as, given
// the player's yaw and the clicked block face. Blocks with no known facing
// state are returned unchanged.
pub fn (p &BlockPalette) oriented(id int, yaw f32, click_face int) int {
	v := p.variant(id) or { return id }
	look := look_facing(yaw)
	// Furnaces/chests/pumpkins present their front to the player.
	front := opposite(look)
	if 'minecraft:cardinal_direction' in v.states {
		return p.with_state(id, 'minecraft:cardinal_direction', cardinal_string(front)) or { id }
	}
	if 'weirdo_direction' in v.states {
		mut nid := p.with_state(id, 'weirdo_direction', weirdo_value(look).str()) or { id }
		if click_face == 0 && 'upside_down_bit' in v.states {
			nid = p.with_state(nid, 'upside_down_bit', '1') or { nid }
		}
		return nid
	}
	if 'facing_direction' in v.states {
		return p.with_state(id, 'facing_direction', facing_direction_value(front).str()) or { id }
	}
	if 'pillar_axis' in v.states {
		return p.with_state(id, 'pillar_axis', axis_from_face(click_face)) or { id }
	}
	return id
}
