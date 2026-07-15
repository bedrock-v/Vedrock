module world

import os

const palette_path = os.join_path('data', 'block_palette.nbt')

fn load_test_palette() ?&BlockPalette {
	if !os.exists(palette_path) {
		return none
	}
	return load_palette(palette_path) or { return none }
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
	assert p.oriented(furnace_south, 0.0, 1) == 1875646683 // north
	assert p.oriented(furnace_south, 180.0, 1) == -831469991 // south
	assert p.oriented(furnace_south, 90.0, 1) == -256712944 // look west, front east
	assert p.oriented(furnace_south, 270.0, 1) == -1816729862 // look east, front west
}

fn test_stairs_weirdo() {
	p := load_test_palette() or { return }
	stairs := -1054044407 // weirdo 0, upside 0
	assert p.oriented(stairs, 270.0, 1) == -1054044407 // look east -> weirdo 0
	assert p.oriented(stairs, 90.0, 1) == -992569584 // look west -> weirdo 1
	assert p.oriented(stairs, 0.0, 1) == -1176994053 // look south -> weirdo 2
	assert p.oriented(stairs, 180.0, 1) == -1115519230 // look north -> weirdo 3
}

fn test_pillar_axis() {
	p := load_test_palette() or { return }
	log_y := 825916963
	assert p.oriented(log_y, 0.0, 1) == 825916963 // top face -> y
	assert p.oriented(log_y, 0.0, 4) == -229389608 // west face -> x
	assert p.oriented(log_y, 0.0, 2) == 1881223534 // north face -> z
}

fn test_facing_direction() {
	p := load_test_palette() or { return }
	ladder_north := 1417289498 // facing_direction 2
	// yaw 0 looks south, front north -> facing_direction 2
	assert p.oriented(ladder_north, 0.0, 1) == 1417289498
	// yaw 180 looks north, front south -> facing_direction 3
	assert p.oriented(ladder_north, 180.0, 1) == 1355814675
}

fn test_non_directional_unchanged() {
	p := load_test_palette() or { return }
	assert p.oriented(stone.network_id, 123.0, 1) == stone.network_id
}
