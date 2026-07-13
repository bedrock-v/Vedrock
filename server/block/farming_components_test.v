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
