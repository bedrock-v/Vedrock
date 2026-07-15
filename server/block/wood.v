module block

import server.world

// Wood family blocks: logs, bark covered wood blocks (and their stripped counterparts),
// planks, leaves and saplings.
// None of these carry unique behaviour yet (no leaf decay, no sapling growth timer), so
// they're built directly as SimpleBlock values from small data tables
// rather than one named class per combination.

const pillar_wood_types = ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'mangrove',
	'cherry', 'pale_oak']
const planks_wood_types = ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'mangrove',
	'cherry', 'bamboo', 'crimson', 'warped', 'pale_oak']
const leaves_wood_types = pillar_wood_types
const sapling_wood_types = ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak', 'cherry',
	'bamboo', 'pale_oak']

const wood_pillar_hardness = f32(2.0)
const planks_hardness = f32(2.0)
const leaves_hardness = f32(0.2)
const sapling_hardness = f32(0.0)

fn pillar_block(name string, axis string, hardness f32) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'pillar_axis'
			kind:       world.state_kind_string
			string_val: axis
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: hardness
	}
}

fn leaves_block(name string, persistent u8, update u8, hardness f32) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'persistent_bit'
			kind:       world.state_kind_byte
			byte_value: persistent
		},
		world.BlockState{
			key:        'update_bit'
			kind:       world.state_kind_byte
			byte_value: update
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: hardness
	}
}

fn sapling_block(name string, age u8, hardness f32) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'age_bit'
			kind:       world.state_kind_byte
			byte_value: age
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: hardness
	}
}

fn simple_wood_block(name string, hardness f32) Block {
	id := 'minecraft:${name}'
	return SimpleBlock{
		id:             id
		block_runtime:  world.new_block(id).network_id
		break_hardness: hardness
	}
}

pub fn wood_blocks() []Block {
	mut result := []Block{}
	for t in pillar_wood_types {
		for shape in ['log', 'wood'] {
			for prefix in ['', 'stripped_'] {
				name := '${prefix}${t}_${shape}'
				for axis in ['x', 'y', 'z'] {
					result << pillar_block(name, axis, wood_pillar_hardness)
				}
			}
		}
	}
	for t in planks_wood_types {
		result << simple_wood_block('${t}_planks', planks_hardness)
	}
	for t in leaves_wood_types {
		for persistent in [u8(0), 1] {
			for update in [u8(0), 1] {
				result << leaves_block('${t}_leaves', persistent, update, leaves_hardness)
			}
		}
	}
	for t in sapling_wood_types {
		for age in [u8(0), 1] {
			result << sapling_block('${t}_sapling', age, sapling_hardness)
		}
	}
	return result
}
