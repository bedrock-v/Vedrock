module world

const expected_nether_lava_level = 31

fn test_flat_generator_matches_vanilla_superflat_preset() {
	g := FlatGenerator{}
	chunk := g.generate(0, 0)
	assert chunk.block_id(0, overworld.min_y, 0) == bedrock.network_id
	assert chunk.block_id(0, overworld.min_y + 1, 0) == dirt.network_id
	assert chunk.block_id(0, overworld.min_y + 2, 0) == dirt.network_id
	assert chunk.block_id(0, overworld.min_y + 3, 0) == grass_block.network_id
	assert g.block_at(0, overworld.min_y, 0) == bedrock.network_id
	assert g.block_at(0, overworld.min_y + 1, 0) == dirt.network_id
}

fn test_generator_registry_has_builtins() {
	r := new_generator_registry()
	names := r.names()
	assert 'void' in names
	assert 'flat' in names
	assert 'normal' in names
	assert 'nether' in names
	assert 'end' in names
}

fn test_generator_registry_create_unknown_returns_none() {
	r := new_generator_registry()
	if _ := r.create('moon', dim: overworld) {
		assert false, 'unregistered generator name should not resolve'
	}
}

fn test_generator_registry_register_overrides_builtin() {
	mut r := new_generator_registry()
	r.register('flat', fn (opts GeneratorOptions) Generator {
		return VoidGenerator{
			dim: opts.dim
		}
	})
	gen := r.create('flat', dim: overworld) or { panic('expected flat to resolve') }
	assert !gen.uses_blocks()
}

fn test_generator_registry_builds_dimension_sized_chunks() {
	r := new_generator_registry()
	flat := r.create('flat', dim: nether) or { panic('expected flat to resolve') }
	chunk := flat.generate(0, 0)

	assert chunk.subchunk_count == nether.subchunk_count
	assert chunk.block_id(0, nether.min_y, 0) == bedrock.network_id
	assert chunk.block_id(0, nether.min_y + 3, 0) == grass_block.network_id
	assert flat.spawn_point().y == nether.min_y + 4
}

fn assert_standable(g Generator, x int, y int, z int) {
	assert g.block_at(x, y - 1, z) != air.network_id
	assert g.block_at(x, y, z) == air.network_id
	assert g.block_at(x, y + 1, z) == air.network_id
}

fn test_flat_and_normal_spawn_are_standable() {
	flat := FlatGenerator{}
	assert_standable(flat, 0, flat.spawn_point().y, 0)

	normal := NormalGenerator{}
	spawn_y := normal.spawn_point().y
	assert spawn_y >= overworld.min_y && spawn_y <= overworld.max_y()
	assert_standable(normal, 0, spawn_y, 0)
	assert normal.block_at(0, overworld.min_y - 1, 0) == air.network_id
}

fn test_a_seeded_world_spawns_on_dry_land() {
	for seed in [i64(8), 9, 12, 1, 2, -7] {
		g := NormalGenerator{
			seed: seed
		}
		p := g.spawn_point()
		assert_standable(g, p.x, p.y, p.z)
		floor := g.block_at(p.x, p.y - 1, p.z)
		assert floor != water.network_id && floor != lava.network_id, 'seed ${seed} spawns on liquid'
		if g.biome_at(0, 0) in [biome_ocean, biome_river] {
			assert p.x != 0 || p.z != 0, 'seed ${seed} spawns over water at the origin'
		}
	}
}

fn test_normal_generator_has_bedrock_floor_and_covered_surface() {
	g := NormalGenerator{}
	chunk := g.generate(0, 0)
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			assert chunk.block_id(x, 0, z) == bedrock.network_id
			mut top := 0
			for y := 127; y > 0; y-- {
				if chunk.block_id(x, y, z) != air.network_id {
					top = y
					break
				}
			}
			assert top > 0, 'column ${x},${z} generated no terrain'
			assert chunk.block_id(x, top, z) != stone.network_id, 'column ${x},${z} has bare stone at the surface'
		}
	}
}

fn test_normal_generator_fills_columns_below_sea_level_with_water() {
	g := NormalGenerator{}
	chunk := g.generate(20, 11)
	mut water_count := 0
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			for y in 0 .. 128 {
				if chunk.block_id(x, y, z) == water.network_id {
					water_count++
					assert y <= 62
				}
			}
		}
	}
	assert water_count > 0
}

fn test_nether_generator_has_bedrock_floor_roof_and_safe_spawn() {
	g := NetherGenerator{}
	chunk := g.generate(0, 0)
	spawn_y := g.spawn_point().y
	assert chunk.block_id(0, nether.min_y, 0) == bedrock.network_id
	assert chunk.block_id(0, nether.max_y() - 1, 0) == netherrack.network_id
	assert chunk.block_id(0, nether.max_y(), 0) == bedrock.network_id
	assert spawn_y > expected_nether_lava_level + 1
	assert_standable(g, 0, spawn_y, 0)
	assert g.block_at(0, nether.max_y(), 0) == bedrock.network_id
	assert g.block_at(0, nether.max_y() - 1, 0) == netherrack.network_id
	assert g.block_at(0, nether.min_y, 0) == bedrock.network_id
	assert g.biome_at(0, 0) == biome_hell
}

fn test_nether_density_is_3d_and_vertically_shaped() {
	g := NetherGenerator{}
	x := 37
	z := -19
	middle := g.density_at(x, 64, z)
	assert g.density_at(x, 8, z) > middle
	assert g.density_at(x, 116, z) > middle
	mut delta := g.density_at(x, 56, z) - g.density_at(x, 72, z)
	if delta < 0 {
		delta = -delta
	}
	assert delta > 0.01
}

fn test_nether_generator_has_cavernous_mid_band_not_empty_shell() {
	g := NetherGenerator{}
	chunk := g.generate(0, 0)
	mut air_count := 0
	mut solid_count := 0
	mut lava_count := 0
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			for y in 32 .. 96 {
				id := chunk.block_id(x, y, z)
				if id == air.network_id {
					air_count++
				} else if id == lava.network_id {
					lava_count++
				} else {
					solid_count++
				}
			}
		}
	}
	assert solid_count > 512
	assert air_count > 512
	assert lava_count == 0
}

fn test_end_generator_has_bedrock_floor_and_spawn_platform_near_origin() {
	g := EndGenerator{}
	spawn_chunk := g.generate(0, 0)
	floor_top_y := the_end.min_y + 3
	platform_y := the_end.min_y + 4
	assert spawn_chunk.block_id(0, the_end.min_y, 0) == bedrock.network_id
	assert spawn_chunk.block_id(2, floor_top_y, 2) == end_stone.network_id
	assert spawn_chunk.block_id(2, platform_y, 2) == obsidian.network_id
	assert g.block_at(2, platform_y, 2) == obsidian.network_id
	assert g.spawn_point().y == platform_y
	assert g.biome_at(0, 0) == biome_the_end
}

fn test_generator_registry_void_and_normal_respect_dimension() {
	r := new_generator_registry()
	void := r.create('void', dim: the_end) or { panic('expected void to resolve') }
	assert void.generate(0, 0).subchunk_count == the_end.subchunk_count

	normal := r.create('normal', dim: nether) or { panic('expected normal to resolve') }
	chunk := normal.generate(0, 0)
	assert chunk.subchunk_count == nether.subchunk_count
	assert normal.spawn_point().y >= nether.min_y && normal.spawn_point().y <= nether.max_y()
}

fn test_density_column_matches_full_grid_sampling() {
	g := NormalGenerator{}
	grid := build_density_grid(64, -32, fn [g] (x int, y int, z int) f64 {
		return g.terrain_noise(x, y, z)
	})
	mut column := []f64{len: density_grid_y}
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			fill_density_column(mut column, grid, x, z)
			for y in 0 .. 128 {
				delta := density_from_grid(grid, x, y, z) - density_from_column(column, y)
				assert delta < 1e-9 && delta > -1e-9
			}
		}
	}
}


fn test_normal_generator_carves_caves_below_surface() {
	g := NormalGenerator{}
	// sample several chunks to find carved air below terrain
	mut carved_air := 0
	mut carved_lava := 0
	for cx in -2 .. 3 {
		for cz in -2 .. 3 {
			chunk := g.generate(cx, cz)
			for x in 0 .. 16 {
				for z in 0 .. 16 {
					mut found_surface := false
					for y := 127; y > 0; y-- {
						id := chunk.block_id(x, y, z)
						if !found_surface && id != air.network_id && id != water.network_id {
							found_surface = true
							continue
						}
						if found_surface && id == air.network_id {
							carved_air++
						}
						if found_surface && id == lava.network_id && y <= normal_cave_lava_level {
							carved_lava++
						}
					}
				}
			}
		}
	}
	assert carved_air > 100, 'expected caves to carve air pockets below terrain'
	assert carved_lava > 0, 'expected lava in caves below y=${normal_cave_lava_level}'
}

fn test_normal_generator_caves_preserve_bedrock() {
	g := NormalGenerator{}
	for cx in -1 .. 2 {
		for cz in -1 .. 2 {
			chunk := g.generate(cx, cz)
			for x in 0 .. 16 {
				for z in 0 .. 16 {
					assert chunk.block_id(x, 0, z) == bedrock.network_id, 'cave carving broke bedrock floor at chunk ${cx},${cz} column ${x},${z}'
				}
			}
		}
	}
}

fn test_normal_generator_caves_dont_break_surface() {
	g := NormalGenerator{}
	chunk := g.generate(0, 0)
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			// find topmost solid block
			mut top := 0
			for y := 127; y > 0; y-- {
				id := chunk.block_id(x, y, z)
				if id != air.network_id && id != water.network_id {
					top = y
					break
				}
			}
			assert top > 0, 'column ${x},${z} has no terrain after carving'
		}
	}
}

fn test_normal_generator_block_at_has_caves() {
	g := NormalGenerator{}
	mut carved := 0
	for x in 0 .. 64 {
		for z in 0 .. 64 {
			for y := 1; y < 60; y++ {
				if g.block_at(x, y, z) == air.network_id {
					carved++
				}
			}
		}
	}
	assert carved > 0, 'expected block_at to reflect cave carving'
}
