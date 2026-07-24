module item

import server.world

fn test_redstone_dust_places_wire() {
	r := new_registry()
	dust := r.get('minecraft:redstone') or { panic('missing redstone item') }
	expected := world.new_block_with_states('minecraft:redstone_wire', [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	assert dust.block_runtime_id() == expected.network_id
}

fn test_repeater_and_comparator_item_ids() {
	r := new_registry()
	assert r.get('minecraft:repeater') != none
	assert r.get('minecraft:comparator') != none
	assert r.get('minecraft:unpowered_repeater') == none
	assert r.get('minecraft:unpowered_comparator') == none
}

fn test_button_and_plate_family_items() {
	r := new_registry()
	wooden := r.get('minecraft:wooden_button') or { panic('missing wooden_button item') }
	stone := r.get('minecraft:stone_button') or { panic('missing stone_button item') }
	plate := r.get('minecraft:heavy_weighted_pressure_plate') or {
		panic('missing heavy_weighted_pressure_plate item')
	}
	assert wooden.max_stack_size() == 64
	assert stone.block_runtime_id() != 0
	assert plate.block_runtime_id() != 0
}

fn test_no_item_for_runtime_only_states() {
	r := new_registry()
	assert r.get('minecraft:daylight_detector_inverted') == none
	assert r.get('minecraft:lit_redstone_lamp') == none
}
