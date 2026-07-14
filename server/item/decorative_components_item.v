module item

import server.world

// Item side of the decorative-components (see server/block/decorative_components.v).

const dye_colors = ['white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray',
	'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black']
const sign_wood_types = planks_wood_types

fn glazed_terracotta_block_color(color string) string {
	return if color == 'light_gray' { 'silver' } else { color }
}

fn simple_color_item(name string) BlockItem {
	id := 'minecraft:${name}'
	return BlockItem{
		id:            id
		block_runtime: world.new_block(id).network_id
	}
}

fn glazed_terracotta_item(color string) BlockItem {
	id := 'minecraft:${glazed_terracotta_block_color(color)}_glazed_terracotta'
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

fn candle_item(name string) BlockItem {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'candles'
			kind:      world.state_kind_int
			int_value: 0
		},
		world.BlockState{
			key:        'lit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn sign_block_name(wood_type string) string {
	prefix := match wood_type {
		'oak' { '' }
		'dark_oak' { 'darkoak_' }
		else { '${wood_type}_' }
	}

	return 'minecraft:${prefix}standing_sign'
}

fn sign_item(wood_type string) BlockItem {
	runtime := world.new_block_with_states(sign_block_name(wood_type), [
		world.BlockState{
			key:       'ground_sign_direction'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            'minecraft:${wood_type}_sign'
		block_runtime: runtime.network_id
	}
}

fn banner_item() BlockItem {
	id := 'minecraft:banner'
	runtime := world.new_block_with_states('minecraft:standing_banner', [
		world.BlockState{
			key:       'ground_sign_direction'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

fn bed_item() BlockItem {
	id := 'minecraft:bed'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'direction'
			kind:      world.state_kind_int
			int_value: 0
		},
		world.BlockState{
			key:        'head_piece_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
		world.BlockState{
			key:        'occupied_bit'
			kind:       world.state_kind_byte
			byte_value: 0
		},
	])
	return BlockItem{
		id:            id
		block_runtime: runtime.network_id
	}
}

pub fn decorative_items() []Item {
	mut result := []Item{}
	result << Item(simple_color_item('glass'))
	result << simple_color_item('glass_pane')
	result << simple_color_item('hardened_clay')
	for color in dye_colors {
		result << simple_color_item('${color}_wool')
		result << simple_color_item('${color}_carpet')
		result << simple_color_item('${color}_concrete')
		result << simple_color_item('${color}_concrete_powder')
		result << simple_color_item('${color}_terracotta')
		result << simple_color_item('${color}_stained_glass')
		result << simple_color_item('${color}_stained_glass_pane')
	}
	for color in dye_colors {
		result << glazed_terracotta_item(color)
	}
	result << candle_item('candle')
	for color in dye_colors {
		result << candle_item('${color}_candle')
	}
	for wood_type in sign_wood_types {
		result << sign_item(wood_type)
	}
	result << banner_item()
	result << bed_item()
	return result
}
