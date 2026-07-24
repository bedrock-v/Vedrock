module item

import server.world

// CarrotItem is the class for 'minecraft:carrot'. No
// separate seed item exists (unlike wheat/beetroot).
pub struct CarrotItem {
	FoodItem
pub:
	block_runtime int
}

pub fn (i CarrotItem) block_runtime_id() int {
	return i.block_runtime
}

pub fn (i CarrotItem) use_on_block_result(block_name string, meta int) ?UseOnBlockResult {
	return compost_result(block_name)
}

pub fn new_carrot() CarrotItem {
	runtime := world.new_block_with_states('minecraft:carrots', [
		world.BlockState{
			key:       'growth'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return CarrotItem{
		FoodItem:      FoodItem{
			id:             'minecraft:carrot'
			food_points:    3
			saturation_mod: 3.6
		}
		block_runtime: runtime.network_id
	}
}
