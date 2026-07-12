module item

import server.world

fn test_wood_item_places_upright() {
	r := new_registry()
	log := r.get('minecraft:oak_log') or { panic('missing oak_log item') }
	expected := world.new_block_with_states('minecraft:oak_log', [
		world.BlockState{
			key:        'pillar_axis'
			kind:       world.state_kind_string
			string_val: 'y'
		},
	])
	assert log.block_runtime_id() == expected.network_id
	assert log.max_stack_size() == 64
}

fn test_stripped_wood_item_is_distinct() {
	r := new_registry()
	regular := r.get('minecraft:oak_wood') or { panic('missing oak_wood item') }
	stripped := r.get('minecraft:stripped_oak_wood') or { panic('missing stripped_oak_wood item') }
	assert regular.block_runtime_id() != stripped.block_runtime_id()
}

fn test_leaves_item_is_persistent() {
	r := new_registry()
	leaves := r.get('minecraft:oak_leaves') or { panic('missing oak_leaves item') }
	expected := world.new_block_with_states('minecraft:oak_leaves', [
		world.BlockState{
			key:        'persistent_bit'
			kind:       world.state_kind_byte
			byte_value: u8(1)
		},
		world.BlockState{
			key:        'update_bit'
			kind:       world.state_kind_byte
			byte_value: u8(0)
		},
	])
	assert leaves.block_runtime_id() == expected.network_id
}

fn test_sapling_item_is_unripe() {
	r := new_registry()
	sapling := r.get('minecraft:bamboo_sapling') or { panic('missing bamboo_sapling item') }
	expected := world.new_block_with_states('minecraft:bamboo_sapling', [
		world.BlockState{
			key:        'age_bit'
			kind:       world.state_kind_byte
			byte_value: u8(0)
		},
	])
	assert sapling.block_runtime_id() == expected.network_id
}

fn test_planks_item_registered_for_nether_wood() {
	r := new_registry()
	it := r.get('minecraft:warped_planks') or { panic('missing warped_planks item') }
	assert it.max_stack_size() == 64
	assert it.block_runtime_id() != 0
}

fn test_invalid_wood_item_combos_not_registered() {
	r := new_registry()
	if _ := r.get('minecraft:bamboo_log') {
		panic('bamboo_log should not be registered as an item')
	}
	if _ := r.get('minecraft:mangrove_sapling') {
		panic('mangrove_sapling should not be registered as an item')
	}
}
