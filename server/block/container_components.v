module block

import server.world

// Container family: chest, trapped chest, barrel, furnace (blast furnace, smoker),
// hopper, dispenser, asdropper, shulker box(es). None of these carry inventory
// storage, smelting or item transfer behaviour yet.

const shulker_colors = ['white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray',
	'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black']

const chest_hardness = f32(2.5)
const barrel_hardness = f32(2.5)
const furnace_hardness = f32(3.5)
const hopper_hardness = f32(3.0)
const dispenser_hardness = f32(3.5)
const shulker_hardness = f32(2.0)

fn cardinal_container_block(name string, direction string, hardness f32) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'minecraft:cardinal_direction'
			kind:       world.state_kind_string
			string_val: direction
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: hardness
	}
}

fn facing_bit_block(name string, bit_key string, facing int, bit_value u8, hardness f32) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'facing_direction'
			kind:      world.state_kind_int
			int_value: facing
		},
		world.BlockState{
			key:        bit_key
			kind:       world.state_kind_byte
			byte_value: bit_value
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: hardness
	}
}

fn simple_container_block(name string, hardness f32) Block {
	id := 'minecraft:${name}'
	return SimpleBlock{
		id:             id
		block_runtime:  world.new_block(id).network_id
		break_hardness: hardness
	}
}

pub fn container_blocks() []Block {
	mut result := []Block{}
	for direction in cardinal_directions {
		result << cardinal_container_block('chest', direction, chest_hardness)
		result << cardinal_container_block('trapped_chest', direction, chest_hardness)
		result << cardinal_container_block('furnace', direction, furnace_hardness)
		result << cardinal_container_block('lit_furnace', direction, furnace_hardness)
		result << cardinal_container_block('blast_furnace', direction, furnace_hardness)
		result << cardinal_container_block('lit_blast_furnace', direction, furnace_hardness)
		result << cardinal_container_block('smoker', direction, furnace_hardness)
		result << cardinal_container_block('lit_smoker', direction, furnace_hardness)
	}
	for facing in 0 .. 6 {
		for bit in [u8(0), 1] {
			result << facing_bit_block('barrel', 'open_bit', facing, bit, barrel_hardness)
			result << facing_bit_block('hopper', 'toggle_bit', facing, bit, hopper_hardness)
			result << facing_bit_block('dispenser', 'triggered_bit', facing, bit,
				dispenser_hardness)
			result << facing_bit_block('dropper', 'triggered_bit', facing, bit, dispenser_hardness)
		}
	}
	result << simple_container_block('undyed_shulker_box', shulker_hardness)
	for color in shulker_colors {
		result << simple_container_block('${color}_shulker_box', shulker_hardness)
	}
	return result
}
