module item

import server.world

const pillar_wood_types = ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'mangrove',
	'cherry', 'pale_oak']
const planks_wood_types = ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'mangrove',
	'cherry', 'bamboo', 'crimson', 'warped', 'pale_oak']
const leaves_wood_types = pillar_wood_types
const sapling_wood_types = ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'cherry',
	'bamboo', 'pale_oak']

fn upright_pillar_item(name string) BlockItem {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'pillar_axis'
			kind:       world.state_kind_string
			string_val: 'y'
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn persistent_leaves_item(name string) BlockItem {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
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
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn unripe_sapling_item(name string) BlockItem {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'age_bit'
			kind:       world.state_kind_byte
			byte_value: u8(0)
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn simple_wood_item(name string) BlockItem {
	id := 'minecraft:${name}'
	return BlockItem{
		id:            id
		block_runtime: world.new_block(id).network_id
	}
}

pub fn wood_items() []Item {
	mut result := []Item{}
	for t in pillar_wood_types {
		for shape in ['log', 'wood'] {
			for prefix in ['', 'stripped_'] {
				result << Item(upright_pillar_item('${prefix}${t}_${shape}'))
			}
		}
	}
	for t in planks_wood_types {
		result << Item(simple_wood_item('${t}_planks'))
	}
	for t in leaves_wood_types {
		result << Item(persistent_leaves_item('${t}_leaves'))
	}
	for t in sapling_wood_types {
		result << Item(unripe_sapling_item('${t}_sapling'))
	}
	return result
}
