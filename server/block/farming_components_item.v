module block

import server.world

// Item side of the farming family (see farming_components.v).

fn seed_item(id string, crop_name string) BlockItem {
	runtime := world.new_block_with_states('minecraft:${crop_name}', [
		world.BlockState{
			key:       'growth'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn composter_item() BlockItem {
	id := 'minecraft:composter'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'composter_fill_level'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

pub fn farming_items() []BlockItem {
	mut result := []BlockItem{}
	result << seed_item('minecraft:wheat_seeds', 'wheat')
	result << seed_item('minecraft:beetroot_seeds', 'beetroot')
	result << composter_item()
	return result
}
