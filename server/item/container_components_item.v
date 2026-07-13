module item

import server.world

// Item side of the container family (see server/block/container_components.v).

const shulker_colors = ['white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray',
	'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black']

fn cardinal_container_item(name string) BlockItem {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'minecraft:cardinal_direction'
			kind:       world.state_kind_string
			string_val: 'south'
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn facing_bit_item(name string, bit_key string) BlockItem {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'facing_direction'
			kind:      world.state_kind_int
			int_value: 0
		},
		world.BlockState{
			key:        bit_key
			kind:       world.state_kind_byte
			byte_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn simple_container_item(name string) BlockItem {
	id := 'minecraft:${name}'
	return BlockItem{
		id:            id
		block_runtime: world.new_block(id).network_id
	}
}

pub fn container_items() []Item {
	mut result := []Item{}
	result << Item(cardinal_container_item('chest'))
	result << cardinal_container_item('trapped_chest')
	result << cardinal_container_item('furnace')
	result << cardinal_container_item('blast_furnace')
	result << cardinal_container_item('smoker')
	result << facing_bit_item('barrel', 'open_bit')
	result << facing_bit_item('hopper', 'toggle_bit')
	result << facing_bit_item('dispenser', 'triggered_bit')
	result << facing_bit_item('dropper', 'triggered_bit')
	result << simple_container_item('undyed_shulker_box')
	for color in shulker_colors {
		result << simple_container_item('${color}_shulker_box')
	}
	return result
}
