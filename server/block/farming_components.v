module block

import server.world

// Farming family: wheat/carrots/potatoes/beetroot crops, farmland, composter.
// Wheat ticks its growth stage forward (see WheatBlock); carrots/potatoes/
// beetroot/farmland/composter don't carry growth timer, moisture-tick or
// compost-fill behaviour yet.

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

// WheatBlock is the class for 'minecraft:wheat'. Its growth stages (0-7)
// tick forward via random_tick.
//
// This is a deliberate simplification, not vanilla parity: it only checks
// for farmland underneath, not light level, haste, or bonemeal adjacent
// growth rate boosts.
pub struct WheatBlock {
	SimpleBlock
	next_growth_id int // 0 once fully grown (growth=7) - no further tick
	farmland_ids   []int
}

pub fn (b WheatBlock) random_tick(x int, y int, z int, mut w TickWorld) {
	if b.next_growth_id == 0 {
		return
	}
	below := w.block_id(x, y - 1, z)
	if below !in b.farmland_ids {
		return
	}
	w.set_block(x, y, z, b.next_growth_id)
}

fn wheat_blocks() []Block {
	mut growth_ids := []int{cap: 8}
	for growth in 0 .. 8 {
		growth_ids << world.new_block_with_states('minecraft:wheat', [
			world.BlockState{
				key:       'growth'
				kind:      world.state_kind_int
				int_value: growth
			},
		]).network_id
	}
	mut farmland_ids := []int{cap: 8}
	for moisture in 0 .. 8 {
		farmland_ids << world.new_block_with_states('minecraft:farmland', [
			world.BlockState{
				key:       'moisturized_amount'
				kind:      world.state_kind_int
				int_value: moisture
			},
		]).network_id
	}
	mut result := []Block{cap: 8}
	for growth in 0 .. 8 {
		next := if growth < 7 { growth_ids[growth + 1] } else { 0 }
		result << Block(WheatBlock{
			SimpleBlock:    SimpleBlock{
				id:             'minecraft:wheat'
				block_runtime:  growth_ids[growth]
				break_hardness: crop_hardness
			}
			next_growth_id: next
			farmland_ids:   farmland_ids
		})
	}
	return result
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
	result << wheat_blocks()
	for name in ['carrots', 'potatoes', 'beetroot'] {
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
