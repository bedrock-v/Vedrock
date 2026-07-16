module block

import server.world

// Farming family: wheat/carrots/potatoes/beetroot crops, farmland, composter.
// None of these carry growth-timer, moisture-tick or compost-fill behaviour yet.

const crop_hardness = f32(0.0)
const farmland_hardness = f32(0.6)
const composter_hardness = f32(0.6)

fn crop_block(name string, growth int) Block {
	id := 'minecraft:${name}'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'growth'
			kind:      world.state_kind_int
			int_value: growth
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: crop_hardness
	}
}

fn farmland_block(moisture int) Block {
	id := 'minecraft:farmland'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'moisturized_amount'
			kind:      world.state_kind_int
			int_value: moisture
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: farmland_hardness
	}
}

fn composter_block(fill_level int) Block {
	id := 'minecraft:composter'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'composter_fill_level'
			kind:      world.state_kind_int
			int_value: fill_level
		},
	])
	return SimpleBlock{
		id:             id
		block_runtime:  runtime.network_id
		break_hardness: composter_hardness
	}
}

pub fn farming_blocks() []Block {
	mut result := []Block{}
	for name in ['wheat', 'carrots', 'potatoes', 'beetroot'] {
		for growth in 0 .. 8 {
			result << crop_block(name, growth)
		}
	}
	for moisture in 0 .. 8 {
		result << farmland_block(moisture)
	}
	for fill in 0 .. 9 {
		result << composter_block(fill)
	}
	return result
}
