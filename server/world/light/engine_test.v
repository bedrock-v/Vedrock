module light

// Grid is an in-memory BlockSource for tests. It stores block ids in a flat
// array over a region and reports air for anything outside it.
struct Grid {
	region Region
mut:
	ids []int
}

fn new_grid(region Region) &Grid {
	return &Grid{
		region: region
		ids:    []int{len: region.volume()}
	}
}

fn (g &Grid) get_block(x int, y int, z int) int {
	if !g.region.contains(x, y, z) {
		return air
	}
	return g.ids[g.region.index(x, y, z)]
}

fn (mut g Grid) set_block(x int, y int, z int, id int) {
	if g.region.contains(x, y, z) {
		g.ids[g.region.index(x, y, z)] = id
	}
}

// abs is a tiny helper - V's math.abs is float-only.
fn abs(v int) int {
	return if v < 0 { -v } else { v }
}

// emitter falloff: level at manhattan distance d is max(0, emission - d) when the
// path is unobstructed air.
fn test_emitter_falloff() {
	region := new_region(0, 0, 0, 30, 5, 30)
	mut grid := new_grid(region)
	grid.set_block(10, 2, 10, glowstone)

	g := compute(region, grid) or { panic('compute failed') }

	assert g.block_light_at(10, 2, 10) == 15
	for d in 0 .. 16 {
		x := 10 + d
		want := if 15 - d > 0 { u8(15 - d) } else { u8(0) }
		assert g.block_light_at(x, 2, 10) == want
	}
	// A diagonal in-plane cell is at manhattan distance dx+dz.
	assert g.block_light_at(13, 2, 14) == u8(15 - (3 + 4))
	assert g.block_light_at(11, 3, 12) == u8(15 - (1 + 1 + 2))
}

// torch emits 14, redstone_torch 7 - check the table drives the seed level.
fn test_emission_levels() {
	region := new_region(0, 0, 0, 10, 2, 0)
	mut grid := new_grid(region)
	grid.set_block(5, 1, 0, torch)
	g := compute(region, grid) or { panic('compute failed') }
	assert g.block_light_at(5, 1, 0) == 14
	assert g.block_light_at(6, 1, 0) == 13

	mut grid2 := new_grid(region)
	grid2.set_block(5, 1, 0, redstone_torch)
	g2 := compute(region, grid2) or { panic('compute failed') }
	assert g2.block_light_at(5, 1, 0) == 7
	assert g2.block_light_at(6, 1, 0) == 6
}

// An opaque wall between the emitter and a target must block block light - the
// target may only be lit by going around the wall, not through it.
fn test_opaque_wall_blocks() {
	region := new_region(0, 0, 0, 6, 0, 2)
	mut grid := new_grid(region)
	// Emitter at x=0. Wall of stone across the whole z-span at x=3.
	grid.set_block(0, 0, 1, glowstone)
	for z in 0 .. 3 {
		grid.set_block(3, 0, z, stone)
	}
	g := compute(region, grid) or { panic('compute failed') }

	// The wall cell itself is opaque - no light passes through it.
	assert g.block_light_at(3, 0, 1) == 0
	// Behind the wall, on the same row, must be dark since the only straight path
	// is blocked and the region is too thin to go around.
	assert g.block_light_at(4, 0, 1) == 0
	assert g.block_light_at(5, 0, 1) == 0
	// In front of the wall light still spreads normally.
	assert g.block_light_at(2, 0, 1) == 13
}

// water attenuates light by an extra level per block on top of the normal step.
fn test_water_attenuation() {
	region := new_region(0, 0, 0, 8, 0, 0)
	mut grid := new_grid(region)
	grid.set_block(0, 0, 0, glowstone)
	for x in 1 .. 5 {
		grid.set_block(x, 0, 0, water)
	}
	g := compute(region, grid) or { panic('compute failed') }
	// x=1: 15 - (1 step + 2 filter) = 12. Each further water block costs 3.
	assert g.block_light_at(1, 0, 0) == 12
	assert g.block_light_at(2, 0, 0) == 9
	assert g.block_light_at(3, 0, 0) == 6
	assert g.block_light_at(4, 0, 0) == 3
}

// Open columns fill to full sky light, top to bottom.
fn test_sky_light_open_column() {
	region := new_region(0, 0, 0, 3, 10, 3)
	mut grid := new_grid(region)
	g := compute(region, grid) or { panic('compute failed') }
	for y in 0 .. 11 {
		assert g.sky_light_at(1, y, 1) == 15
	}
}

// An overhang blocks the direct sky above and the cells beneath it are only lit
// by sky light bleeding in from the sides, so they attenuate.
fn test_sky_light_overhang() {
	region := new_region(0, 0, 0, 6, 6, 0)
	mut grid := new_grid(region)
	// Solid roof across x=0..3 at y=5. x=4..6 stays open to the sky.
	for x in 0 .. 4 {
		grid.set_block(x, 5, 0, stone)
	}
	g := compute(region, grid) or { panic('compute failed') }

	// Open side is full sky light all the way down.
	assert g.sky_light_at(5, 0, 0) == 15
	assert g.sky_light_at(6, 3, 0) == 15
	// Directly under the roof at the same level as open sky the light bleeds in
	// from the open column and drops off by distance.
	assert g.sky_light_at(3, 4, 0) == 14 // one step from the open x=4 column
	assert g.sky_light_at(2, 4, 0) == 13
	// The roof cell itself is opaque.
	assert g.sky_light_at(2, 5, 0) == 0
	// Deep under the roof, far from the open edge, is dark.
	assert g.sky_light_at(0, 4, 0) == 11
}

// Removing an emitter clears its light and re-propagates the neighbourhood.
fn test_remove_emitter_clears() {
	region := new_region(0, 0, 0, 20, 0, 0)
	mut grid := new_grid(region)
	grid.set_block(10, 0, 0, glowstone)
	mut g := compute(region, grid) or { panic('compute failed') }
	assert g.block_light_at(10, 0, 0) == 15
	assert g.block_light_at(13, 0, 0) == 12

	// Remove it from the world, then tell the engine.
	grid.set_block(10, 0, 0, air)
	g.remove_light(grid, 10, 0, 0)

	for x in 0 .. 21 {
		assert g.block_light_at(x, 0, 0) == 0
	}
}

// Removing one emitter next to another must keep the surviving emitter's light.
fn test_remove_with_second_emitter() {
	region := new_region(0, 0, 0, 20, 0, 0)
	mut grid := new_grid(region)
	grid.set_block(5, 0, 0, glowstone)
	grid.set_block(15, 0, 0, glowstone)
	mut g := compute(region, grid) or { panic('compute failed') }

	grid.set_block(5, 0, 0, air)
	g.remove_light(grid, 5, 0, 0)

	// The removed emitter's cell is now lit only by the survivor: distance 10 -> 5.
	assert g.block_light_at(5, 0, 0) == 5
	// The survivor is untouched.
	assert g.block_light_at(15, 0, 0) == 15
	assert g.block_light_at(12, 0, 0) == 12
}

// Adding an emitter incrementally lights its neighbourhood without a full recompute.
fn test_add_emitter_incremental() {
	region := new_region(0, 0, 0, 20, 0, 0)
	mut grid := new_grid(region)
	mut g := compute(region, grid) or { panic('compute failed') }
	assert g.block_light_at(10, 0, 0) == 0

	grid.set_block(10, 0, 0, glowstone)
	g.add_light(grid, 10, 0, 0)
	assert g.block_light_at(10, 0, 0) == 15
	assert g.block_light_at(13, 0, 0) == 12
	assert g.block_light_at(16, 0, 0) == 9
}

// The volume cap rejects an oversized region instead of allocating.
fn test_volume_cap() {
	over := new_region(0, 0, 0, 200, 200, 200)
	assert over.volume() > max_volume
	mut grid := new_grid(new_region(0, 0, 0, 1, 1, 1))
	if _ := compute(over, grid) {
		assert false, 'oversized region should return none'
	}
}

// Sanity check on the table helpers themselves.
fn test_table() {
	assert emission(glowstone) == 15
	assert emission(sea_lantern) == 15
	assert emission(lava) == 15
	assert emission(torch) == 14
	assert emission(redstone_torch) == 7
	assert emission(air) == 0
	assert emission(stone) == 0
	assert opaque(stone)
	assert !opaque(air)
	assert !opaque(water)
	assert !opaque(glowstone)
	assert filter(water) == 2
	assert filter(leaves) == 1
}
