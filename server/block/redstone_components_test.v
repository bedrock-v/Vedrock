module block

import server.world

fn test_redstone_wire_signal_variants() {
	r := new_registry()
	lit := world.new_block_with_states('minecraft:redstone_wire', [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: 15
		},
	])
	unlit := world.new_block_with_states('minecraft:redstone_wire', [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	assert lit.network_id != unlit.network_id
	by_lit := r.get(lit.network_id) or { panic('missing redstone_wire signal=15') }
	assert by_lit.hardness() == 0.0
	assert by_lit.breakable()
}

fn test_repeater_item_id_differs_from_block_id() {
	r := new_registry()
	assert r.get_by_name('minecraft:unpowered_repeater') != none
	assert r.get_by_name('minecraft:powered_repeater') != none
	assert r.get_by_name('minecraft:repeater') == none
}

fn test_button_family_registered() {
	r := new_registry()
	wooden := r.get_by_name('minecraft:wooden_button') or { panic('missing wooden_button') }
	stone := r.get_by_name('minecraft:stone_button') or { panic('missing stone_button') }
	blackstone := r.get_by_name('minecraft:polished_blackstone_button') or {
		panic('missing polished_blackstone_button')
	}
	assert wooden.hardness() == 0.5
	assert stone.hardness() == 0.5
	assert blackstone.hardness() == 0.5
}

fn test_pressure_plate_family_registered() {
	r := new_registry()
	assert r.get_by_name('minecraft:light_weighted_pressure_plate') != none
	assert r.get_by_name('minecraft:heavy_weighted_pressure_plate') != none
	assert r.get_by_name('minecraft:stone_pressure_plate') != none
}

fn test_observer_and_piston_hardness() {
	r := new_registry()
	observer := r.get_by_name('minecraft:observer') or { panic('missing observer') }
	piston := r.get_by_name('minecraft:piston') or { panic('missing piston') }
	sticky := r.get_by_name('minecraft:sticky_piston') or { panic('missing sticky_piston') }
	assert observer.hardness() == 3.0
	assert piston.hardness() == 1.5
	assert sticky.hardness() == 1.5
}

fn test_lamp_daylight_and_tripwire_registered() {
	r := new_registry()
	assert r.get_by_name('minecraft:redstone_lamp') != none
	assert r.get_by_name('minecraft:lit_redstone_lamp') != none
	assert r.get_by_name('minecraft:daylight_detector') != none
	assert r.get_by_name('minecraft:daylight_detector_inverted') != none
	assert r.get_by_name('minecraft:tripwire_hook') != none
	assert r.get_by_name('minecraft:trip_wire') != none
}
