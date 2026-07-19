module block

import server.world

// Decorative-components family: wool, carpet, concrete, terracotta,
// stained glass(and pane), candles, signs, banners, bed.

pub const dye_colors = ['white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray',
	'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black']

fn glazed_terracotta_block_color(color string) string {
	return if color == 'light_gray' { 'silver' } else { color }
}

const sign_wood_types = planks_wood_types

const wool_hardness = f32(0.8)
const carpet_hardness = f32(0.1)
const concrete_hardness = f32(1.8)
const concrete_powder_hardness = f32(0.5)
const terracotta_hardness = f32(1.25)
const glazed_terracotta_hardness = f32(1.4)
const glass_hardness = f32(0.3)
const candle_hardness = f32(0.1)
const sign_hardness = f32(1.0)
const banner_hardness = f32(1.0)
const bed_hardness = f32(0.2)

fn stateless_color_block(name string, hardness f32) Block {
	id := 'minecraft:${name}'
	return SimpleBlock{
		id:             id
		block_runtime:  world.new_block(id).network_id
		break_hardness: hardness
	}
}

fn glazed_terracotta_block(color string, facing int) Block {
	id := 'minecraft:${glazed_terracotta_block_color(color)}_glazed_terracotta'
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
		break_hardness: glazed_terracotta_hardness
	}
}

fn candle_block(name string, count int, lit u8) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'candles'
			kind:      world.state_kind_int
			int_value: count
		},
		world.BlockState{
			key:        'lit'
			kind:       world.state_kind_byte
			byte_value: lit
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: candle_hardness
	}
}

fn candle_cake_block(name string, lit u8) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:        'lit'
			kind:       world.state_kind_byte
			byte_value: lit
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: candle_hardness
	}
}

fn sign_block_name(wood_type string, shape string) string {
	prefix := match wood_type {
		'oak' { '' }
		'dark_oak' { 'darkoak_' }
		else { '${wood_type}_' }
	}

	return 'minecraft:${prefix}${shape}'
}

pub struct SignBlock {
	SimpleBlock
}

fn standing_sign_block(wood_type string, direction int) Block {
	id := sign_block_name(wood_type, 'standing_sign')
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'ground_sign_direction'
			kind:      world.state_kind_int
			int_value: direction
		},
	])
	return SignBlock{
		SimpleBlock: SimpleBlock{
			id:             id
			block_runtime:  runtime.network_id
			break_hardness: sign_hardness
		}
	}
}

fn wall_sign_block(wood_type string, facing int) Block {
	id := sign_block_name(wood_type, 'wall_sign')
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'facing_direction'
			kind:      world.state_kind_int
			int_value: facing
		},
	])
	return SignBlock{
		SimpleBlock: SimpleBlock{
			id:             id
			block_runtime:  runtime.network_id
			break_hardness: sign_hardness
		}
	}
}

fn standing_banner_block(direction int) Block {
	id := 'minecraft:standing_banner'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'ground_sign_direction'
			kind:      world.state_kind_int
			int_value: direction
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: banner_hardness
	}
}

fn wall_banner_block(facing int) Block {
	id := 'minecraft:wall_banner'
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
		break_hardness: banner_hardness
	}
}

fn bed_block(direction int, head_piece u8, occupied u8) Block {
	id := 'minecraft:bed'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'direction'
			kind:      world.state_kind_int
			int_value: direction
		},
		world.BlockState{
			key:        'head_piece_bit'
			kind:       world.state_kind_byte
			byte_value: head_piece
		},
		world.BlockState{
			key:        'occupied_bit'
			kind:       world.state_kind_byte
			byte_value: occupied
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: bed_hardness
	}
}

pub fn decorative_blocks() []Block {
	mut result := []Block{}
	result << stateless_color_block('glass', glass_hardness)
	result << stateless_color_block('glass_pane', glass_hardness)
	result << stateless_color_block('hardened_clay', terracotta_hardness)
	for color in dye_colors {
		result << stateless_color_block('${color}_wool', wool_hardness)
		result << stateless_color_block('${color}_carpet', carpet_hardness)
		result << stateless_color_block('${color}_concrete', concrete_hardness)
		result << stateless_color_block('${color}_concrete_powder', concrete_powder_hardness)
		result << stateless_color_block('${color}_terracotta', terracotta_hardness)
		result << stateless_color_block('${color}_stained_glass', glass_hardness)
		result << stateless_color_block('${color}_stained_glass_pane', glass_hardness)
	}
	for color in dye_colors {
		for facing in 0 .. 6 {
			result << glazed_terracotta_block(color, facing)
		}
	}
	mut candle_names := ['candle']
	mut candle_cake_names := ['candle_cake']
	for color in dye_colors {
		candle_names << '${color}_candle'
		candle_cake_names << '${color}_candle_cake'
	}
	for name in candle_names {
		for count in 0 .. 4 {
			for lit in [u8(0), 1] {
				result << candle_block(name, count, lit)
			}
		}
	}
	for name in candle_cake_names {
		for lit in [u8(0), 1] {
			result << candle_cake_block(name, lit)
		}
	}
	for wood_type in sign_wood_types {
		for direction in 0 .. 16 {
			result << standing_sign_block(wood_type, direction)
		}
		for facing in 0 .. 6 {
			result << wall_sign_block(wood_type, facing)
		}
	}
	for direction in 0 .. 16 {
		result << standing_banner_block(direction)
	}
	for facing in 0 .. 6 {
		result << wall_banner_block(facing)
	}
	for direction in 0 .. 4 {
		for head_piece in [u8(0), 1] {
			for occupied in [u8(0), 1] {
				result << bed_block(direction, head_piece, occupied)
			}
		}
	}
	return result
}
