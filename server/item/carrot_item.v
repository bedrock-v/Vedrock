module item

// CarrotItem is the class for 'minecraft:carrot'.
pub struct CarrotItem {
	FoodItem
}

pub fn new_carrot() CarrotItem {
	return CarrotItem{
		FoodItem: FoodItem{
			id:             'minecraft:carrot'
			food_points:    3
			saturation_mod: 3.6
		}
	}
}
