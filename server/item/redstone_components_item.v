module item

import server.world

// Item side of the redstone component family (see server/block/redstone_components.v).

const button_types = ['wooden', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'crimson',
	'warped', 'mangrove', 'cherry', 'bamboo', 'pale_oak', 'stone', 'polished_blackstone']
const plate_types = ['wooden', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'crimson', 'warped',
	'mangrove', 'cherry', 'bamboo', 'pale_oak', 'stone', 'light_weighted', 'heavy_weighted',
	'polished_blackstone']

fn redstone_wire_item() BlockItem {
	id := 'minecraft:redstone'
	runtime := world.new_block_with_states('minecraft:redstone_wire', [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn redstone_torch_item() BlockItem {
	id := 'minecraft:redstone_torch'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'torch_facing_direction'
			kind:       world.state_kind_string
			string_val: 'top'
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn redstone_lamp_item() BlockItem {
	id := 'minecraft:redstone_lamp'
	return BlockItem{
		id:            id
		block_runtime: world.new_block(id).network_id
	}
}

fn repeater_item() BlockItem {
	runtime := world.new_block_with_states('minecraft:unpowered_repeater', [
		world.BlockState{
			key:        'minecraft:cardinal_direction'
			kind:       world.state_kind_string
			string_val: 'south'
		},
		world.BlockState{
			key:       'repeater_delay'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            'minecraft:repeater'
		block_runtime: runtime.network_id
	}
}

fn comparator_item() BlockItem {
	runtime := world.new_block_with_states('minecraft:unpowered_comparator', [
		world.BlockState{
			key:        'minecraft:cardinal_direction'
			kind:       world.state_kind_string
			string_val: 'south'
		},
		world.BlockState{
			key:        'output_lit_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
		world.BlockState{
			key:        'output_subtract_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
	])
	return BlockItem{
		id:            'minecraft:comparator'
		block_runtime: runtime.network_id
	}
}

fn lever_item() BlockItem {
	id := 'minecraft:lever'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'lever_direction'
			kind:       world.state_kind_string
			string_val: 'east'
		},
		world.BlockState{
			key:        'open_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn observer_item() BlockItem {
	id := 'minecraft:observer'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'minecraft:facing_direction'
			kind:       world.state_kind_string
			string_val: 'down'
		},
		world.BlockState{
			key:        'powered_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn piston_item(name string) BlockItem {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'facing_direction'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn daylight_detector_item() BlockItem {
	id := 'minecraft:daylight_detector'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn tripwire_hook_item() BlockItem {
	id := 'minecraft:tripwire_hook'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'attached_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
		world.BlockState{
			key:       'direction'
			kind:      world.state_kind_int
			int_value: 0
		},
		world.BlockState{
			key:        'powered_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn button_item(name string) BlockItem {
	id := 'minecraft:${name}_button'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'button_pressed_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
		world.BlockState{
			key:       'facing_direction'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn plate_item(name string) BlockItem {
	id := 'minecraft:${name}_pressure_plate'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

pub fn redstone_component_items() []Item {
	mut result := []Item{}
	result << Item(redstone_torch_item())
	result << redstone_lamp_item()
	result << repeater_item()
	result << comparator_item()
	result << lever_item()
	result << observer_item()
	result << piston_item('piston')
	result << piston_item('sticky_piston')
	result << daylight_detector_item()
	result << tripwire_hook_item()
	for name in button_types {
		result << button_item(name)
	}
	for name in plate_types {
		result << plate_item(name)
	}
	return result
}
