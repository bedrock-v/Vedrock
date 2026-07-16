module block

import server.world

// Combat & progression family: enchanting table, bookshelf, anvil, grindstone, brewing stand, cauldron.

const anvil_directions = ['south', 'west', 'north', 'east']
const grindstone_attachments = ['standing', 'hanging', 'side', 'multiple']
const cauldron_liquids = ['water', 'lava', 'powder_snow']

const enchanting_table_hardness = f32(5.0)
const bookshelf_hardness = f32(1.5)
const anvil_hardness = f32(5.0)
const grindstone_hardness = f32(2.0)
const brewing_stand_hardness = f32(0.5)
const cauldron_hardness = f32(2.0)

fn anvil_block(name string, direction string) Block {
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
		break_hardness: anvil_hardness
	}
}

fn grindstone_block(attachment string, direction int) Block {
	id := 'minecraft:grindstone'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'attachment'
			kind:       world.state_kind_string
			string_val: attachment
		},
		world.BlockState{
			key:       'direction'
			kind:      world.state_kind_int
			int_value: direction
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: grindstone_hardness
	}
}

fn brewing_stand_block(slot_a u8, slot_b u8, slot_c u8) Block {
	id := 'minecraft:brewing_stand'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'brewing_stand_slot_a_bit'
			kind:       world.state_kind_byte
			byte_value: slot_a
		},
		world.BlockState{
			key:        'brewing_stand_slot_b_bit'
			kind:       world.state_kind_byte
			byte_value: slot_b
		},
		world.BlockState{
			key:        'brewing_stand_slot_c_bit'
			kind:       world.state_kind_byte
			byte_value: slot_c
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: brewing_stand_hardness
	}
}

fn cauldron_block(liquid string, fill_level int) Block {
	id := 'minecraft:cauldron'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'cauldron_liquid'
			kind:       world.state_kind_string
			string_val: liquid
		},
		world.BlockState{
			key:       'fill_level'
			kind:      world.state_kind_int
			int_value: fill_level
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: cauldron_hardness
	}
}

fn stateless_combat_block(name string, hardness f32) Block {
	id := 'minecraft:${name}'
	return SimpleBlock{
		id:             id
		block_runtime:  world.new_block(id).network_id
		break_hardness: hardness
	}
}

pub fn combat_progression_blocks() []Block {
	mut result := []Block{}
	result << stateless_combat_block('enchanting_table', enchanting_table_hardness)
	result << stateless_combat_block('bookshelf', bookshelf_hardness)
	for direction in anvil_directions {
		result << anvil_block('anvil', direction)
		result << anvil_block('chipped_anvil', direction)
		result << anvil_block('damaged_anvil', direction)
		result << anvil_block('deprecated_anvil', direction)
	}
	for attachment in grindstone_attachments {
		for direction in 0 .. 4 {
			result << grindstone_block(attachment, direction)
		}
	}
	for slot_a in [u8(0), 1] {
		for slot_b in [u8(0), 1] {
			for slot_c in [u8(0), 1] {
				result << brewing_stand_block(slot_a, slot_b, slot_c)
			}
		}
	}
	for liquid in cauldron_liquids {
		for fill_level in 0 .. 7 {
			result << cauldron_block(liquid, fill_level)
		}
	}
	return result
}
