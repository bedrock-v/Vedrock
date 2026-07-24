module item

// BeefItem is the class for 'minecraft:beef'.
pub struct BeefItem {
	FoodItem
}

pub fn new_beef() BeefItem {
	return BeefItem{
		FoodItem: FoodItem{
			id:             'minecraft:beef'
			food_points:    3
			saturation_mod: 1.8
		}
	}
}
