module item

// AppleItem is the class for 'minecraft:apple'.
pub struct AppleItem {
	FoodItem
}

pub fn new_apple() AppleItem {
	return AppleItem{
		FoodItem: FoodItem{
			id:             'minecraft:apple'
			food_points:    4
			saturation_mod: 2.4
		}
	}
}
