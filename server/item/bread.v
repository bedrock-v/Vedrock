module item

// BreadItem is the class for 'minecraft:bread'.
pub struct BreadItem {
	FoodItem
}

pub fn new_bread() BreadItem {
	return BreadItem{
		FoodItem: FoodItem{
			id:             'minecraft:bread'
			food_points:    5
			saturation_mod: 6.0
		}
	}
}
