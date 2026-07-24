module block

import server.world

fn test_crop_growth_stages_registered() {
	r := new_registry()
	for name in ['minecraft:wheat', 'minecraft:carrots', 'minecraft:potatoes', 'minecraft:beetroot'] {
		stage0 := world.new_block_with_states(name, [
			world.BlockState{
				key:       'growth'
				kind:      world.state_kind_int
				int_value: 0
			},
		])
		stage7 := world.new_block_with_states(name, [
			world.BlockState{
				key:       'growth'
				kind:      world.state_kind_int
				int_value: 7
			},
		])
		assert stage0.network_id != stage7.network_id
		b := r.get(stage7.network_id) or { panic('missing ${name} growth=7') }
		assert b.hardness() == 0.0
	}
}

fn test_farmland_moisture_variants() {
	r := new_registry()
	dry := world.new_block_with_states('minecraft:farmland', [
		world.BlockState{
			key:       'moisturized_amount'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	wet := world.new_block_with_states('minecraft:farmland', [
		world.BlockState{
			key:       'moisturized_amount'
			kind:      world.state_kind_int
			int_value: 7
		},
	])
	assert dry.network_id != wet.network_id
	b := r.get(dry.network_id) or { panic('missing farmland moisturized_amount=0') }
	assert b.hardness() == 0.6
}

fn test_composter_fill_levels_registered() {
	r := new_registry()
	empty := world.new_block_with_states('minecraft:composter', [
		world.BlockState{
			key:       'composter_fill_level'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	full := world.new_block_with_states('minecraft:composter', [
		world.BlockState{
			key:       'composter_fill_level'
			kind:      world.state_kind_int
			int_value: 8
		},
	])
	assert empty.network_id != full.network_id
	b := r.get(full.network_id) or { panic('missing composter composter_fill_level=8') }
	assert b.hardness() == 0.6
}

// FakeTickWorld is a minimal in memory TickWorld fixture for testing
// RandomTicker blocks without a real db.World.
struct FakeTickWorld {
mut:
	blocks map[string]int
}

fn (w &FakeTickWorld) block_id(x int, y int, z int) int {
	return w.blocks['${x}:${y}:${z}'] or { 0 }
}

fn (mut w FakeTickWorld) set_block(x int, y int, z int, id int) {
	w.blocks['${x}:${y}:${z}'] = id
}

fn (mut w FakeTickWorld) schedule_tick(x int, y int, z int, delay int) {}

fn test_wheat_growth_chains_stages_on_farmland() {
	blocks := wheat_blocks()
	assert blocks.len == 8

	stage0 := blocks[0]
	stage1 := blocks[1]
	assert stage0 is WheatBlock
	assert stage0 is RandomTicker

	if stage0 is WheatBlock {
		mut w := FakeTickWorld{}
		w.set_block(0, -1, 0, stage0.farmland_ids[0])
		stage0.random_tick(0, 0, 0, mut w)
		assert w.block_id(0, 0, 0) == stage1.runtime_id()
	} else {
		assert false
	}
}

fn test_wheat_growth_noop_without_farmland() {
	blocks := wheat_blocks()
	stage0 := blocks[0]
	if stage0 is WheatBlock {
		mut w := FakeTickWorld{}
		w.set_block(0, -1, 0, 0) // not a farmland id
		stage0.random_tick(0, 0, 0, mut w)
		assert w.block_id(0, 0, 0) == 0
	} else {
		assert false
	}
}

fn test_wheat_fully_grown_stage_never_advances() {
	blocks := wheat_blocks()
	stage7 := blocks[7]
	if stage7 is WheatBlock {
		assert stage7.next_growth_id == 0
		mut w := FakeTickWorld{}
		w.set_block(0, -1, 0, stage7.farmland_ids[0])
		stage7.random_tick(0, 0, 0, mut w)
		assert w.block_id(0, 0, 0) == 0
	} else {
		assert false
	}
}

fn test_wheat_registered_via_farming_blocks_in_real_registry() {
	r := new_registry()
	stage0_id := wheat_blocks()[0].runtime_id()
	got := r.get(stage0_id) or { panic('missing wheat stage 0') }
	assert got is WheatBlock
	assert got.hardness() == crop_hardness
}
