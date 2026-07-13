module block

import server.world

// Redstone component family: dust, torch, repeater, comparator, lever,
// button family (14 variants), pressure plates, lamp, observer, piston (+sticky),
// daylight sensor, tripwire hook/wire.

const button_types = ['wooden', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'crimson',
	'warped', 'mangrove', 'cherry', 'bamboo', 'pale_oak', 'stone', 'polished_blackstone']
const plate_types = ['wooden', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'crimson', 'warped',
	'mangrove', 'cherry', 'bamboo', 'pale_oak', 'stone', 'light_weighted', 'heavy_weighted',
	'polished_blackstone']
const lever_directions = ['down_east_west', 'east', 'west', 'south', 'north', 'up_north_south',
	'up_east_west', 'down_north_south']
const cardinal_directions = ['south', 'west', 'north', 'east']
const observer_facings = ['down', 'up', 'north', 'south', 'west', 'east']
const torch_facings = ['unknown', 'west', 'east', 'north', 'south', 'top']

const wire_hardness = f32(0.0)
const torch_hardness = f32(0.0)
const repeater_hardness = f32(0.0)
const comparator_hardness = f32(0.0)
const lever_hardness = f32(0.5)
const lamp_hardness = f32(0.3)
const observer_hardness = f32(3.0)
const piston_hardness = f32(1.5)
const daylight_hardness = f32(0.2)
const tripwire_hardness = f32(0.0)
const button_hardness = f32(0.5)
const plate_hardness = f32(0.5)

fn redstone_wire_block(signal int) Block {
	id := 'minecraft:redstone_wire'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: signal
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: wire_hardness
	}
}

fn torch_block(name string, facing string) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'torch_facing_direction'
			kind:       world.state_kind_string
			string_val: facing
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: torch_hardness
	}
}

fn repeater_block(name string, direction string, delay int) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'minecraft:cardinal_direction'
			kind:       world.state_kind_string
			string_val: direction
		},
		world.BlockState{
			key:       'repeater_delay'
			kind:      world.state_kind_int
			int_value: delay
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: repeater_hardness
	}
}

fn comparator_block(name string, direction string, lit u8, subtract u8) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'minecraft:cardinal_direction'
			kind:       world.state_kind_string
			string_val: direction
		},
		world.BlockState{
			key:        'output_lit_bit'
			kind:       world.state_kind_byte
			byte_value: lit
		},
		world.BlockState{
			key:        'output_subtract_bit'
			kind:       world.state_kind_byte
			byte_value: subtract
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: comparator_hardness
	}
}

fn lever_block(direction string, open u8) Block {
	id := 'minecraft:lever'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'lever_direction'
			kind:       world.state_kind_string
			string_val: direction
		},
		world.BlockState{
			key:        'open_bit'
			kind:       world.state_kind_byte
			byte_value: open
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: lever_hardness
	}
}

fn observer_block(facing string, powered u8) Block {
	id := 'minecraft:observer'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'minecraft:facing_direction'
			kind:       world.state_kind_string
			string_val: facing
		},
		world.BlockState{
			key:        'powered_bit'
			kind:       world.state_kind_byte
			byte_value: powered
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: observer_hardness
	}
}

fn piston_block(name string, facing int) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'facing_direction'
			kind:      world.state_kind_int
			int_value: facing
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: piston_hardness
	}
}

fn daylight_block(name string, signal int) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: signal
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: daylight_hardness
	}
}

fn tripwire_hook_block(attached u8, direction int, powered u8) Block {
	id := 'minecraft:tripwire_hook'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'attached_bit'
			kind:       world.state_kind_byte
			byte_value: attached
		},
		world.BlockState{
			key:       'direction'
			kind:      world.state_kind_int
			int_value: direction
		},
		world.BlockState{
			key:        'powered_bit'
			kind:       world.state_kind_byte
			byte_value: powered
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: tripwire_hardness
	}
}

fn trip_wire_block(attached u8, disarmed u8, powered u8, suspended u8) Block {
	id := 'minecraft:trip_wire'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'attached_bit'
			kind:       world.state_kind_byte
			byte_value: attached
		},
		world.BlockState{
			key:        'disarmed_bit'
			kind:       world.state_kind_byte
			byte_value: disarmed
		},
		world.BlockState{
			key:        'powered_bit'
			kind:       world.state_kind_byte
			byte_value: powered
		},
		world.BlockState{
			key:        'suspended_bit'
			kind:       world.state_kind_byte
			byte_value: suspended
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: tripwire_hardness
	}
}

fn button_block(name string, pressed u8, facing int) Block {
	id := 'minecraft:${name}_button'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'button_pressed_bit'
			kind:       world.state_kind_byte
			byte_value: pressed
		},
		world.BlockState{
			key:       'facing_direction'
			kind:      world.state_kind_int
			int_value: facing
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: button_hardness
	}
}

fn plate_block(name string, signal int) Block {
	id := 'minecraft:${name}_pressure_plate'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: signal
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: plate_hardness
	}
}

fn simple_redstone_block(name string, hardness f32) Block {
	id := 'minecraft:${name}'
	return SimpleBlock{
		id:             id
		block_runtime:  world.new_block(id).network_id
		break_hardness: hardness
	}
}

pub fn redstone_component_blocks() []Block {
	mut result := []Block{}
	for signal in 0 .. 16 {
		result << redstone_wire_block(signal)
	}
	for facing in torch_facings {
		result << torch_block('redstone_torch', facing)
		result << torch_block('unlit_redstone_torch', facing)
	}
	for direction in cardinal_directions {
		for delay in 0 .. 4 {
			result << repeater_block('unpowered_repeater', direction, delay)
			result << repeater_block('powered_repeater', direction, delay)
		}
	}
	for direction in cardinal_directions {
		for lit in [u8(0), 1] {
			for subtract in [u8(0), 1] {
				result << comparator_block('unpowered_comparator', direction, lit, subtract)
				result << comparator_block('powered_comparator', direction, lit, subtract)
			}
		}
	}
	for direction in lever_directions {
		for open in [u8(0), 1] {
			result << lever_block(direction, open)
		}
	}
	for facing in observer_facings {
		for powered in [u8(0), 1] {
			result << observer_block(facing, powered)
		}
	}
	for facing in 0 .. 6 {
		result << piston_block('piston', facing)
		result << piston_block('sticky_piston', facing)
	}
	result << simple_redstone_block('redstone_lamp', lamp_hardness)
	result << simple_redstone_block('lit_redstone_lamp', lamp_hardness)
	for name in ['daylight_detector', 'daylight_detector_inverted'] {
		for signal in 0 .. 16 {
			result << daylight_block(name, signal)
		}
	}
	for attached in [u8(0), 1] {
		for direction in 0 .. 4 {
			for powered in [u8(0), 1] {
				result << tripwire_hook_block(attached, direction, powered)
			}
		}
	}
	for attached in [u8(0), 1] {
		for disarmed in [u8(0), 1] {
			for powered in [u8(0), 1] {
				for suspended in [u8(0), 1] {
					result << trip_wire_block(attached, disarmed, powered, suspended)
				}
			}
		}
	}
	for name in button_types {
		for pressed in [u8(0), 1] {
			for facing in 0 .. 6 {
				result << button_block(name, pressed, facing)
			}
		}
	}
	for name in plate_types {
		for signal in 0 .. 16 {
			result << plate_block(name, signal)
		}
	}
	return result
}
