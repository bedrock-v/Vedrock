module block

import server.world

fn test_log_axis_variants() {
	r := new_registry()
	y_axis := world.new_block_with_states('minecraft:oak_log', [
		world.BlockState{
			key:        'pillar_axis'
			kind:       world.state_kind_string
			string_val: 'y'
		},
	])
	x_axis := world.new_block_with_states('minecraft:oak_log', [
		world.BlockState{
			key:        'pillar_axis'
			kind:       world.state_kind_string
			string_val: 'x'
		},
	])
	assert y_axis.network_id != x_axis.network_id
	by_y := r.get(y_axis.network_id) or { panic('missing oak_log axis=y') }
	by_x := r.get(x_axis.network_id) or { panic('missing oak_log axis=x') }
	assert by_y.hardness() == 2.0
	assert by_x.hardness() == 2.0
}

fn test_stripped_log_distinct() {
	r := new_registry()
	regular := r.get_by_name('minecraft:oak_log') or { panic('missing oak_log') }
	stripped := r.get_by_name('minecraft:stripped_oak_log') or { panic('missing stripped_oak_log') }
	assert regular.runtime_id() != stripped.runtime_id()
	assert stripped.hardness() == 2.0
}

fn test_leaves_sapling_hardness() {
	r := new_registry()
	leaves := r.get_by_name('minecraft:oak_leaves') or { panic('missing oak_leaves') }
	sapling := r.get_by_name('minecraft:oak_sapling') or { panic('missing oak_sapling') }
	assert leaves.hardness() == 0.2
	assert sapling.hardness() == 0.0
	assert sapling.breakable()
}

fn test_nether_planks_registered() {
	r := new_registry()
	crimson := r.get_by_name('minecraft:crimson_planks') or { panic('missing crimson_planks') }
	assert crimson.hardness() == 2.0
}

fn test_invalid_combos_not_registered() {
	r := new_registry()
	assert r.get_by_name('minecraft:bamboo_log') == none
	assert r.get_by_name('minecraft:crimson_leaves') == none
	assert r.get_by_name('minecraft:mangrove_sapling') == none
}
