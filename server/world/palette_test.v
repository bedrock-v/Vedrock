module world

import os

const palette_path = os.join_path('data', 'block_palette.nbt')

fn load_test_palette() ?&BlockPalette {
	if !os.exists(palette_path) {
		return none
	}
	return load_palette(palette_path) or { return none }
}

fn palette_id_for_test(p &BlockPalette, name string, states map[string]string) int {
	return p.by_key[palette_key(name, states)] or {
		panic('missing palette state ${name} ${states}')
	}
}

fn test_palette_loads() {
	p := load_test_palette() or {
		eprintln('skip: palette not found')
		return
	}
	assert p.len() > 10000
}

fn test_cardinal_facing() {
	p := load_test_palette() or { return }
	// furnace faces the player - yaw 0 looks south, so the front points north.
	furnace_south := -831469991
	assert p.oriented(furnace_south, 0.0, 1, 0.5) == 1875646683 // north
	assert p.oriented(furnace_south, 180.0, 1, 0.5) == -831469991 // south
	assert p.oriented(furnace_south, 90.0, 1, 0.5) == -256712944 // look west, front east
	assert p.oriented(furnace_south, 270.0, 1, 0.5) == -1816729862 // look east, front west
}

fn test_stairs_weirdo() {
	p := load_test_palette() or { return }
	stairs := -1054044407 // weirdo 0, upside 0
	assert p.oriented(stairs, 270.0, 1, 0.5) == -1054044407 // look east -> weirdo 0
	assert p.oriented(stairs, 90.0, 1, 0.5) == -992569584 // look west -> weirdo 1
	assert p.oriented(stairs, 0.0, 1, 0.5) == -1176994053 // look south -> weirdo 2
	assert p.oriented(stairs, 180.0, 1, 0.5) == -1115519230 // look north -> weirdo 3
}

fn test_stairs_upside_down_from_click_height() {
	p := load_test_palette() or { return }
	stairs := palette_id_for_test(p, 'minecraft:oak_stairs', {
		'upside_down_bit':  '0'
		'weirdo_direction': '0'
	})
	upside := palette_id_for_test(p, 'minecraft:oak_stairs', {
		'upside_down_bit':  '1'
		'weirdo_direction': '0'
	})
	assert p.oriented(stairs, 270.0, 3, 0.75) == upside
	assert p.oriented(stairs, 270.0, 1, 0.75) == stairs
	assert p.oriented(stairs, 270.0, 0, 0.25) == upside
}

fn test_pillar_axis() {
	p := load_test_palette() or { return }
	log_y := 825916963
	assert p.oriented(log_y, 0.0, 1, 0.5) == 825916963 // top face -> y
	assert p.oriented(log_y, 0.0, 4, 0.5) == -229389608 // west face -> x
	assert p.oriented(log_y, 0.0, 2, 0.5) == 1881223534 // north face -> z
}

fn test_facing_direction() {
	p := load_test_palette() or { return }
	piston_down := palette_id_for_test(p, 'minecraft:piston', {
		'facing_direction': '0'
	})
	piston_north := palette_id_for_test(p, 'minecraft:piston', {
		'facing_direction': '2'
	})
	piston_south := palette_id_for_test(p, 'minecraft:piston', {
		'facing_direction': '3'
	})
	// yaw 0 looks south, front north -> facing_direction 2
	assert p.oriented(piston_down, 0.0, 1, 0.5) == piston_north
	// yaw 180 looks north, front south -> facing_direction 3
	assert p.oriented(piston_down, 180.0, 1, 0.5) == piston_south
}

fn test_attachment_facing_uses_clicked_face() {
	p := load_test_palette() or { return }
	ladder_north := palette_id_for_test(p, 'minecraft:ladder', {
		'facing_direction': '2'
	})
	ladder_west := palette_id_for_test(p, 'minecraft:ladder', {
		'facing_direction': '4'
	})
	torch_top := palette_id_for_test(p, 'minecraft:redstone_torch', {
		'torch_facing_direction': 'top'
	})
	torch_north := palette_id_for_test(p, 'minecraft:redstone_torch', {
		'torch_facing_direction': 'north'
	})
	assert p.oriented(ladder_north, 0.0, 4, 0.5) == ladder_west
	assert p.oriented(torch_top, 0.0, 2, 0.5) == torch_north
}

fn test_attachment_placement_rejects_invalid_faces() {
	p := load_test_palette() or { return }
	ladder := palette_id_for_test(p, 'minecraft:ladder', {
		'facing_direction': '2'
	})
	torch := palette_id_for_test(p, 'minecraft:redstone_torch', {
		'torch_facing_direction': 'top'
	})
	sign := palette_id_for_test(p, 'minecraft:standing_sign', {
		'ground_sign_direction': '0'
	})
	assert !p.can_place_on_face(ladder, 1)
	assert !p.can_place_on_face(ladder, 0)
	assert p.can_place_on_face(ladder, 2)
	assert !p.can_place_on_face(torch, 0)
	assert p.can_place_on_face(torch, 1)
	assert p.can_place_on_face(torch, 4)
	assert !p.can_place_on_face(sign, 0)
	assert p.can_place_on_face(sign, 1)
	assert p.can_place_on_face(sign, 5)
	assert p.can_place_on_face(stone.network_id, 0)
}

fn test_attachment_placement_requires_support_model() {
	p := load_test_palette() or { return }
	ladder := palette_id_for_test(p, 'minecraft:ladder', {
		'facing_direction': '2'
	})
	torch := palette_id_for_test(p, 'minecraft:redstone_torch', {
		'torch_facing_direction': 'top'
	})
	button := palette_id_for_test(p, 'minecraft:stone_button', {
		'button_pressed_bit': '0'
		'facing_direction':   '1'
	})
	assert p.can_place_on_support(ladder, 2, stone.network_id)
	assert !p.can_place_on_support(ladder, 2, air.network_id)
	assert !p.can_place_on_support(ladder, 2, torch)
	assert !p.can_place_on_support(ladder, 1, stone.network_id)
	assert p.can_place_on_support(torch, 1, stone.network_id)
	assert !p.can_place_on_support(torch, 1, ladder)
	assert p.can_place_on_support(button, 1, stone.network_id)
	assert !p.can_place_on_support(button, 1, torch)
}

fn test_palette_models_common_shapes() {
	p := load_test_palette() or { return }
	ladder := palette_id_for_test(p, 'minecraft:ladder', {
		'facing_direction': '2'
	})
	stairs := palette_id_for_test(p, 'minecraft:oak_stairs', {
		'upside_down_bit':  '0'
		'weirdo_direction': '0'
	})
	upside_stairs := palette_id_for_test(p, 'minecraft:oak_stairs', {
		'upside_down_bit':  '1'
		'weirdo_direction': '0'
	})
	assert p.model(stone.network_id).face_solid(1)
	assert p.model(air.network_id).boxes().len == 0
	assert p.model(ladder).boxes().len == 1
	assert !p.model(ladder).face_solid(2)
	assert p.model(stairs).face_solid(0)
	assert !p.model(stairs).face_solid(1)
	assert p.model(upside_stairs).face_solid(1)
}

fn test_sign_and_banner_switch_to_wall_variants() {
	p := load_test_palette() or { return }
	oak_standing := palette_id_for_test(p, 'minecraft:standing_sign', {
		'ground_sign_direction': '0'
	})
	oak_wall_west := palette_id_for_test(p, 'minecraft:wall_sign', {
		'facing_direction': '4'
	})
	banner_standing := palette_id_for_test(p, 'minecraft:standing_banner', {
		'ground_sign_direction': '0'
	})
	banner_wall_south := palette_id_for_test(p, 'minecraft:wall_banner', {
		'facing_direction': '3'
	})
	assert p.oriented(oak_standing, 0.0, 4, 0.5) == oak_wall_west
	assert p.oriented(banner_standing, 0.0, 3, 0.5) == banner_wall_south
}

fn test_non_directional_unchanged() {
	p := load_test_palette() or { return }
	assert p.oriented(stone.network_id, 123.0, 1, 0.5) == stone.network_id
}

fn test_openable_blocks_toggle_open_bit() {
	p := load_test_palette() or { return }
	door := palette_id_for_test(p, 'minecraft:wooden_door', {
		'door_hinge_bit':               '0'
		'minecraft:cardinal_direction': 'south'
		'open_bit':                     '0'
		'upper_block_bit':              '0'
	})
	trapdoor := palette_id_for_test(p, 'minecraft:trapdoor', {
		'direction':       '0'
		'open_bit':        '0'
		'upside_down_bit': '0'
	})
	gate := palette_id_for_test(p, 'minecraft:fence_gate', {
		'in_wall_bit':                  '0'
		'minecraft:cardinal_direction': 'south'
		'open_bit':                     '0'
	})
	assert p.variant(p.toggled_open(door) or { panic('door did not toggle') }) or {
		panic('missing toggled door')
	}.states['open_bit'] == '1'
	assert p.variant(p.toggled_open(trapdoor) or { panic('trapdoor did not toggle') }) or {
		panic('missing toggled trapdoor')
	}.states['open_bit'] == '1'
	assert p.variant(p.toggled_open(gate) or { panic('gate did not toggle') }) or {
		panic('missing toggled gate')
	}.states['open_bit'] == '1'
}

fn test_door_placement_builds_matching_lower_and_upper_parts() {
	p := load_test_palette() or { return }
	door := palette_id_for_test(p, 'minecraft:wooden_door', {
		'door_hinge_bit':               '0'
		'minecraft:cardinal_direction': 'south'
		'open_bit':                     '0'
		'upper_block_bit':              '0'
	})
	parts := p.door_placement(door, 0.0, NeighborBlockIDs{}) or { panic('door placement failed') }
	lower := p.variant(parts.lower) or { panic('missing lower door') }
	upper := p.variant(parts.upper) or { panic('missing upper door') }
	assert lower.states['upper_block_bit'] == '0'
	assert upper.states['upper_block_bit'] == '1'
	assert lower.states['open_bit'] == upper.states['open_bit']
	assert lower.states['minecraft:cardinal_direction'] == upper.states['minecraft:cardinal_direction']
}

fn test_wall_connections_recompute_palette_state() {
	p := load_test_palette() or { return }
	wall := palette_id_for_test(p, 'minecraft:cobblestone_wall', {
		'wall_connection_type_east':  'none'
		'wall_connection_type_north': 'none'
		'wall_connection_type_south': 'none'
		'wall_connection_type_west':  'none'
		'wall_post_bit':              '0'
	})
	connected := p.connected_block(wall, NeighborBlockIDs{
		east:  stone.network_id
		north: stone.network_id
	})
	v := p.variant(connected) or { panic('missing connected wall') }
	assert v.states['wall_connection_type_east'] == 'short'
	assert v.states['wall_connection_type_north'] == 'short'
	assert v.states['wall_connection_type_south'] == 'none'
	assert v.states['wall_post_bit'] == '1'
}

fn test_slab_merge_uses_double_variant_when_present() {
	p := load_test_palette() or { return }
	oak_bottom := palette_id_for_test(p, 'minecraft:oak_slab', {
		'minecraft:vertical_half': 'bottom'
	})
	merged := p.merged_slab(oak_bottom, oak_bottom, 1, 0.75, true) or {
		panic('slab did not merge')
	}
	v := p.variant(merged) or { panic('missing merged slab') }
	assert v.name == 'minecraft:oak_double_slab'
	assert v.states['minecraft:vertical_half'] == 'bottom'
}

fn test_trapdoor_orientation_uses_stair_direction_encoding() {
	p := load_test_palette() or { return }
	trapdoor := palette_id_for_test(p, 'minecraft:trapdoor', {
		'direction':       '0'
		'open_bit':        '0'
		'upside_down_bit': '0'
	})
	west_top := p.oriented(trapdoor, 90.0, 3, 0.75)
	v := p.variant(west_top) or { panic('missing oriented trapdoor') }
	assert v.states['direction'] == '1'
	assert v.states['upside_down_bit'] == '1'
}
