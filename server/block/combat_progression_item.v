module block

import server.world

// Item side of the combat and progression family (see combat_progression.v).

fn anvil_item(name string) BlockItem {
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

fn grindstone_item() BlockItem {
	id := 'minecraft:grindstone'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'attachment'
			kind:       world.state_kind_string
			string_val: 'standing'
		},
		world.BlockState{
			key:       'direction'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn brewing_stand_item() BlockItem {
	id := 'minecraft:brewing_stand'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'brewing_stand_slot_a_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
		world.BlockState{
			key:        'brewing_stand_slot_b_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
		world.BlockState{
			key:        'brewing_stand_slot_c_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn cauldron_item() BlockItem {
	id := 'minecraft:cauldron'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'cauldron_liquid'
			kind:       world.state_kind_string
			string_val: 'water'
		},
		world.BlockState{
			key:       'fill_level'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn stateless_combat_item(name string) BlockItem {
	id := 'minecraft:${name}'
	return BlockItem{
		id:            id
		block_runtime: world.new_block(id).network_id
	}
}

pub fn combat_progression_items() []BlockItem {
	mut result := []BlockItem{}
	result << stateless_combat_item('enchanting_table')
	result << stateless_combat_item('bookshelf')
	result << anvil_item('anvil')
	result << anvil_item('chipped_anvil')
	result << anvil_item('damaged_anvil')
	result << grindstone_item()
	result << brewing_stand_item()
	result << cauldron_item()
	return result
}
