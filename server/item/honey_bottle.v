module item

// HoneyBottleItem is the class for 'minecraft:honey_bottle'.
pub struct HoneyBottleItem {
	FoodItem
}

pub fn new_honey_bottle() HoneyBottleItem {
	return HoneyBottleItem{
		FoodItem: FoodItem{
			id:             'minecraft:honey_bottle'
			food_points:    6
			saturation_mod: 1.2
			stack_max:      16
		}
	}
}
