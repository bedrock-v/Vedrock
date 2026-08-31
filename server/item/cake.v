module item

// CakeItem is the class for 'minecraft:cake'.
pub struct CakeItem {
	FoodItem
}

pub fn new_cake() CakeItem {
	return CakeItem{
		FoodItem: FoodItem{
			id:             'minecraft:cake'
			food_points:    2
			saturation_mod: 0.4
		}
	}
}
