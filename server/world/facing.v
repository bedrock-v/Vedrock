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

fn facing_from_face(face int) Facing {
	return match face {
		0 { Facing.down }
		1 { Facing.up }
		2 { Facing.north }
		3 { Facing.south }
		4 { Facing.west }
		5 { Facing.east }
		else { Facing.south }
	}
}

fn is_horizontal_face(face int) bool {
	return face >= 2 && face <= 5
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

fn rotate_right(f Facing) Facing {
	return match f {
		.north { Facing.east }
		.east { Facing.south }
		.south { Facing.west }
		.west { Facing.north }
		else { f }
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

fn sign_rotation(yaw f32) int {
	mut y := yaw + 180.0
	for y < 0 {
		y += 360.0
	}
	for y >= 360.0 {
		y -= 360.0
	}
	return int((y * 16.0 / 360.0) + 0.5) & 0xf
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

fn wall_variant_name(name string) ?string {
	if name == 'minecraft:standing_banner' {
		return 'minecraft:wall_banner'
	}
	if name.ends_with('standing_sign') {
		return name.replace('standing_sign', 'wall_sign')
	}
	return none
}

fn (p &BlockPalette) with_named_state(name string, key string, value string) ?int {
	return p.by_key[palette_key(name, {
		key: value
	})] or { return none }
}

// can_place_on_face reports whether a block may be placed from the clicked face.
// It only covers attachment families with face specific restrictions; unknown blocks stay permissive.
pub fn (p &BlockPalette) can_place_on_face(id int, click_face int) bool {
	v := p.variant(id) or { return true }
	if v.name == 'minecraft:ladder' {
		return is_horizontal_face(click_face)
	}
	if 'torch_facing_direction' in v.states {
		return click_face == 1 || is_horizontal_face(click_face)
	}
	if 'ground_sign_direction' in v.states {
		return click_face == 1 || is_horizontal_face(click_face)
	}
	return true
}

// oriented returns the network id the given block should be placed as, given
// the player's yaw and the clicked block face. Blocks with no known facing
// state are returned unchanged.
pub fn (p &BlockPalette) oriented(id int, yaw f32, click_face int, click_y f32) int {
	v := p.variant(id) or { return id }
	look := look_facing(yaw)
	// Furnaces/chests/pumpkins present their front to the player.
	front := opposite(look)
	if 'ground_sign_direction' in v.states {
		if click_face == 1 {
			return p.with_state(id, 'ground_sign_direction', sign_rotation(yaw).str()) or { id }
		}
		if is_horizontal_face(click_face) {
			wall_name := wall_variant_name(v.name) or { return id }
			return p.with_named_state(wall_name, 'facing_direction',
				facing_direction_value(facing_from_face(click_face)).str()) or { id }
		}
		return id
	}
	if 'torch_facing_direction' in v.states {
		if click_face == 1 {
			return p.with_state(id, 'torch_facing_direction', 'top') or { id }
		}
		if is_horizontal_face(click_face) {
			return p.with_state(id, 'torch_facing_direction',
				cardinal_string(facing_from_face(click_face))) or { id }
		}
		return id
	}
	if v.name == 'minecraft:ladder' && is_horizontal_face(click_face) {
		return p.with_state(id, 'facing_direction',
			facing_direction_value(facing_from_face(click_face)).str()) or { id }
	}
	if v.name.ends_with('_button') && 'facing_direction' in v.states {
		return p.with_state(id, 'facing_direction',
			facing_direction_value(facing_from_face(click_face)).str()) or { id }
	}
	if v.name == 'minecraft:lever' && 'lever_direction' in v.states
		&& is_horizontal_face(click_face) {
		return p.with_state(id, 'lever_direction', cardinal_string(facing_from_face(click_face))) or {
			id
		}
	}
	if is_door_name(v.name) && 'minecraft:cardinal_direction' in v.states {
		return p.with_state(id, 'minecraft:cardinal_direction', cardinal_string(rotate_right(look))) or {
			id
		}
	}
	if is_trapdoor_name(v.name) && 'direction' in v.states {
		mut nid := p.with_state(id, 'direction', weirdo_value(look).str()) or { id }
		if (click_face == 0 || (click_y > 0.5 && click_face != 1)) && 'upside_down_bit' in v.states {
			nid = p.with_state(nid, 'upside_down_bit', '1') or { nid }
		}
		return nid
	}
	if 'minecraft:cardinal_direction' in v.states {
		return p.with_state(id, 'minecraft:cardinal_direction', cardinal_string(front)) or { id }
	}
	if 'weirdo_direction' in v.states {
		mut nid := p.with_state(id, 'weirdo_direction', weirdo_value(look).str()) or { id }
		if (click_face == 0 || (click_y > 0.5 && click_face != 1)) && 'upside_down_bit' in v.states {
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

// carved_pumpkin_id returns the carved_pumpkin id matching an uncarved
// pumpkin at id, facing the clicked face directly - or none if id isn't an
// uncarved pumpkin, or the click was on the top/bottom face. Matches
// Dragonfly's Pumpkin.Carve (the carved face is the one clicked, not its
// opposite - unlike oriented()'s player-facing placement logic above) and
// Shears.UseOnBlock (top/bottom faces can't be carved).
pub fn (p &BlockPalette) carved_pumpkin_id(id int, click_face int) ?int {
	v := p.variant(id) or { return none }
	if v.name != 'minecraft:pumpkin' || !is_horizontal_face(click_face) {
		return none
	}
	return p.with_named_state('minecraft:carved_pumpkin', 'minecraft:cardinal_direction',
		cardinal_string(facing_from_face(click_face)))
}
