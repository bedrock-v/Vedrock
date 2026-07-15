module world

pub fn (p &BlockPalette) model(id int) BlockModel {
	v := p.variant(id) or { return solid_model() }
	return model_for_variant(v)
}

fn model_for_variant(v BlockVariant) BlockModel {
	if is_empty_model_name(v.name) {
		return empty_model()
	}
	if v.name == 'minecraft:ladder' {
		return ladder_model(state_int(v.states, 'facing_direction', 2))
	}
	if v.name.ends_with('_slab') || v.name.contains('slab') {
		return slab_model(state_bool(v.states, 'double_stone_slab', false)
			|| state_bool(v.states, 'double_stone_slab2', false), slab_is_top(v.states))
	}
	if v.name.ends_with('_stairs') {
		return stair_model(weirdo_face(state_int(v.states, 'weirdo_direction', 0)), state_bool(v.states,
			'upside_down_bit', false))
	}
	if v.name.ends_with('_fence') || v.name.ends_with('_wall') || v.name.ends_with('_pane')
		|| v.name.ends_with('_bars') {
		return thin_model()
	}
	return solid_model()
}

fn state_int(states map[string]string, key string, fallback int) int {
	v := states[key] or { return fallback }
	return v.int()
}

fn state_bool(states map[string]string, key string, fallback bool) bool {
	v := states[key] or { return fallback }
	return v == '1' || v == 'true' || v == 'top'
}

fn slab_is_top(states map[string]string) bool {
	if v := states['minecraft:vertical_half'] {
		return v == 'top'
	}
	if v := states['top_slot_bit'] {
		return v == '1' || v == 'true'
	}
	return false
}

fn weirdo_face(value int) int {
	return match value {
		0 { 5 }
		1 { 4 }
		2 { 3 }
		3 { 2 }
		else { 5 }
	}
}

fn is_empty_model_name(name string) bool {
	if name == 'minecraft:air' || name == 'minecraft:water' || name == 'minecraft:flowing_water'
		|| name == 'minecraft:lava' || name == 'minecraft:flowing_lava' {
		return true
	}
	if name.contains('torch') || name.ends_with('_button') || name == 'minecraft:lever' {
		return true
	}
	if name.contains('sign') || name.contains('banner') || name.contains('flower')
		|| name.contains('sapling') || name.contains('crop') {
		return true
	}
	if name.ends_with('_rail') || name == 'minecraft:rail' || name.ends_with('_carpet')
		|| name == 'minecraft:redstone_wire' {
		return true
	}
	return false
}

pub fn (p &BlockPalette) can_place_on_support(id int, click_face int, support_id int) bool {
	if !p.can_place_on_face(id, click_face) {
		return false
	}
	v := p.variant(id) or { return true }
	support := p.model(support_id)
	if v.name == 'minecraft:ladder' {
		return support.face_solid(click_face)
	}
	if 'torch_facing_direction' in v.states {
		if click_face == 1 {
			return support.face_center_solid(click_face)
		}
		return support.face_solid(click_face)
	}
	if v.name.ends_with('_button') && 'facing_direction' in v.states {
		return support.face_center_solid(click_face)
	}
	if v.name == 'minecraft:lever' && 'lever_direction' in v.states {
		return support.face_center_solid(click_face)
	}
	if 'ground_sign_direction' in v.states {
		return support.face_center_solid(click_face)
	}
	return true
}
