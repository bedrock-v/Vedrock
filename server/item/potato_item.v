module item

import server.world

// PotatoItem is the class for 'minecraft:potato'. No
// separate seed item exists (unlike wheat/beetroot).
pub struct PotatoItem {
	FoodItem
pub:
	block_runtime int
}

pub fn (i PotatoItem) block_runtime_id() int {
	return i.block_runtime
}

pub fn new_potato() PotatoItem {
	runtime := world.new_block_with_states('minecraft:potatoes', [
		world.BlockState{
			key:       'growth'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return PotatoItem{
		FoodItem:      FoodItem{
			id:             'minecraft:potato'
			food_points:    1
			saturation_mod: 0.6
		}
		block_runtime: runtime.network_id
	}
}
