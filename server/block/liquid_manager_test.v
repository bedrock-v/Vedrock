module block

import server.world

// FakeWorld is an in-memory block grid standing in for Hub. Any coordinate not
// written reads as air, and set_block_id overwrites in place - enough to drive
// and assert the spread engine without a real world.
struct FakeWorld {
mut:
	blocks map[string]int
}

fn (mut w FakeWorld) get_block(x int, y int, z int) int {
	return w.blocks[key(x, y, z)] or { world.air.network_id }
}

fn (mut w FakeWorld) set_block_id(id int, x int, y int, z int) {
	w.blocks[key(x, y, z)] = id
}

fn (mut w FakeWorld) set_solid(x int, y int, z int) {
	w.blocks[key(x, y, z)] = world.stone.network_id
}

// run_ticks drains the manager for up to n ticks or until nothing is pending.
fn run_ticks(mut m LiquidManager, n int) {
	for _ in 0 .. n {
		if m.pending_count() == 0 {
			break
		}
		m.tick()
	}
}

// water_depth returns the internal depth at a cell, or 0 if it isn't water.
fn depth_at(mut m LiquidManager, x int, y int, z int) int {
	w := m.liquid_of_kind_at(.water, x, y, z) or { return 0 }
	return w.depth
}

fn test_source_spreads_to_horizontal_neighbours() {
	mut wld := &FakeWorld{}
	// Solid floor under the source and its ring so water rests and spreads out.
	for dx in -8 .. 9 {
		for dz in -8 .. 9 {
			wld.set_solid(dx, -1, dz)
		}
	}
	mut m := new_manager(wld)
	m.place_source(0, 0, 0)
	run_ticks(mut m, 20)

	assert m.is_liquid_of_kind(.water, 0, 0, 0)
	assert m.is_liquid_of_kind(.water, 1, 0, 0)
	assert m.is_liquid_of_kind(.water, -1, 0, 0)
	assert m.is_liquid_of_kind(.water, 0, 0, 1)
	assert m.is_liquid_of_kind(.water, 0, 0, -1)
}

fn test_flowing_depth_decays_with_distance() {
	mut wld := &FakeWorld{}
	for dx in -8 .. 9 {
		for dz in -8 .. 9 {
			wld.set_solid(dx, -1, dz)
		}
	}
	mut m := new_manager(wld)
	m.place_source(0, 0, 0)
	run_ticks(mut m, 30)

	// Source is full (8), each horizontal step loses one level.
	assert depth_at(mut m, 0, 0, 0) == source_depth
	d1 := depth_at(mut m, 1, 0, 0)
	d2 := depth_at(mut m, 2, 0, 0)
	assert d1 == source_depth - spread_decay
	assert d2 == d1 - spread_decay
	assert d2 < d1
}

fn test_water_flows_down() {
	mut wld := &FakeWorld{}
	// No floor: water should fall straight down as a falling column.
	mut m := new_manager(wld)
	m.place_source(0, 5, 0)
	run_ticks(mut m, 20)

	assert m.is_liquid_of_kind(.water, 0, 4, 0)
	assert m.is_liquid_of_kind(.water, 0, 3, 0)
	below := m.liquid_of_kind_at(.water, 0, 4, 0) or { LiquidState{} }
	assert below.falling
}

fn test_flowing_dries_up_when_source_removed() {
	mut wld := &FakeWorld{}
	for dx in -8 .. 9 {
		for dz in -8 .. 9 {
			wld.set_solid(dx, -1, dz)
		}
	}
	mut m := new_manager(wld)
	m.place_source(0, 0, 0)
	run_ticks(mut m, 30)
	assert m.is_liquid_of_kind(.water, 1, 0, 0)

	// Remove the source and re-notify the region.
	wld.set_block_id(world.air.network_id, 0, 0, 0)
	m.on_block_changed(0, 0, 0)
	run_ticks(mut m, 60)

	assert !m.is_liquid_of_kind(.water, 1, 0, 0)
	assert !m.is_liquid_of_kind(.water, 2, 0, 0)
	assert !m.is_liquid_of_kind(.water, 0, 0, 0)
}

fn test_two_sources_form_new_source() {
	mut wld := &FakeWorld{}
	for dx in -4 .. 5 {
		for dz in -4 .. 5 {
			wld.set_solid(dx, -1, dz)
		}
	}
	mut m := new_manager(wld)
	// Two sources one cell apart. The gap between them is fed from both sides by
	// full-depth flow, so it should promote to a source.
	m.place_source(0, 0, 0)
	m.place_source(2, 0, 0)
	run_ticks(mut m, 40)

	mid := m.liquid_of_kind_at(.water, 1, 0, 0) or { LiquidState{} }
	assert mid.is_source()
}

fn test_per_tick_cap_is_respected() {
	mut wld := &FakeWorld{}
	mut m := new_manager(wld)
	// Queue more cells than the cap and confirm one tick leaves a remainder.
	for i in 0 .. max_cells_per_tick + 50 {
		m.enqueue(i, 0, 0)
	}
	before := m.pending_count()
	m.tick()
	assert before == max_cells_per_tick + 50
	// A tick drains at most the cap; the extras stay queued for next tick.
	assert m.pending_count() >= 50
}

fn test_falling_column_survives_weaker_horizontal_spread() {
	mut wld := &FakeWorld{}
	mut m := new_manager(wld)
	m.set_liquid(new_falling(), 0, 0, 0)

	m.flow_into(new_flowing(3), 0, 0, 0)

	after := m.liquid_of_kind_at(.water, 0, 0, 0) or { panic('expected water') }
	assert after.falling
	assert after.depth == source_depth
}

// lava_depth_at returns the internal depth of a lava cell, or 0 if the block
// there is not lava.
fn lava_depth_at(mut m LiquidManager, x int, y int, z int) int {
	l := m.liquid_of_kind_at(.lava, x, y, z) or { return 0 }
	return l.depth
}

fn solid_floor(mut wld FakeWorld) {
	for dx in -8 .. 9 {
		for dz in -8 .. 9 {
			wld.set_solid(dx, -1, dz)
		}
	}
}

fn test_lava_spreads_less_far_than_water() {
	mut wld := &FakeWorld{}
	solid_floor(mut wld)
	mut m := new_manager(wld)
	m.place_liquid_source(.lava, 0, 0, 0)
	run_ticks(mut m, 200)

	// Decay is 2 per step, so a source at depth 8 reaches three cells out.
	assert lava_depth_at(mut m, 1, 0, 0) == 6
	assert lava_depth_at(mut m, 2, 0, 0) == 4
	assert lava_depth_at(mut m, 3, 0, 0) == 2
	assert lava_depth_at(mut m, 4, 0, 0) == 0
}

fn test_lava_moves_slower_than_water() {
	mut wld := &FakeWorld{}
	solid_floor(mut wld)
	mut m := new_manager(wld)
	m.place_liquid_source(.lava, 0, 0, 0)
	// One tick is not enough for lava: it is held over until its own slower
	// rate comes round.
	m.tick()
	assert !m.is_liquid_of_kind(.lava, 1, 0, 0)
	assert m.pending_count() > 0
	for _ in 0 .. lava_tick_divisor {
		m.tick()
	}
	assert m.is_liquid_of_kind(.lava, 1, 0, 0)
}

fn test_lava_arriving_in_water_makes_stone() {
	mut wld := &FakeWorld{}
	mut m := new_manager(wld)
	m.set_liquid(new_liquid_source(.water), 1, 0, 0)
	m.flow_into(new_liquid_flowing(.lava, 6), 1, 0, 0)

	assert wld.get_block(1, 0, 0) == world.stone.network_id
}

fn test_water_pouring_onto_a_lava_source_makes_obsidian() {
	mut wld := &FakeWorld{}
	mut m := new_manager(wld)
	m.set_liquid(new_liquid_source(.lava), 0, 0, 0)
	m.set_liquid(new_liquid_falling(.water), 0, 1, 0)
	m.process(0, 0, 0)

	assert wld.get_block(0, 0, 0) == world.obsidian.network_id
}

fn test_water_reaching_a_lava_source_makes_obsidian() {
	mut wld := &FakeWorld{}
	solid_floor(mut wld)
	mut m := new_manager(wld)
	m.set_liquid(new_liquid_source(.lava), 1, 0, 0)
	m.place_source(0, 0, 0)
	run_ticks(mut m, 200)

	assert wld.get_block(1, 0, 0) == world.obsidian.network_id
}

fn test_water_reaching_flowing_lava_makes_cobblestone() {
	mut wld := &FakeWorld{}
	solid_floor(mut wld)
	mut m := new_manager(wld)
	m.set_liquid(new_liquid_flowing(.lava, 4), 1, 0, 0)
	m.place_source(0, 0, 0)
	run_ticks(mut m, 200)

	assert wld.get_block(1, 0, 0) == world.cobblestone.network_id
}

fn test_lava_never_forms_a_new_source_between_two_of_them() {
	mut wld := &FakeWorld{}
	solid_floor(mut wld)
	mut m := new_manager(wld)
	m.place_liquid_source(.lava, -1, 0, 0)
	m.place_liquid_source(.lava, 1, 0, 0)
	run_ticks(mut m, 200)

	middle := m.liquid_of_kind_at(.lava, 0, 0, 0) or {
		assert false, 'lava did not reach the gap'
		return
	}
	assert !middle.is_source()
}

fn test_fluid_ids_are_recognised_by_kind() {
	assert is_lava_id(new_liquid_source(.lava).network_id())
	assert is_lava_id(new_liquid_flowing(.lava, 3).network_id())
	assert !is_lava_id(new_source().network_id())
	assert is_water_id(new_flowing(3).network_id())
	assert !is_water_id(world.stone.network_id)
	assert liquid_at_id(world.stone.network_id) == none
}
