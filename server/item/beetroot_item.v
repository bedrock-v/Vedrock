module item

// BeetrootItem is the class for 'minecraft:beetroot'.
pub struct BeetrootItem {
	FoodItem
}

pub fn new_beetroot() BeetrootItem {
	return BeetrootItem{
		FoodItem: FoodItem{
			id:             'minecraft:beetroot'
			food_points:    1
			saturation_mod: 1.2
		}
	}
}
