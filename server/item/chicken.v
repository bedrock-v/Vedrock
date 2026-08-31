module item

// ChickenItem is the class for 'minecraft:chicken'.
pub struct ChickenItem {
	FoodItem
}

pub fn new_chicken() ChickenItem {
	return ChickenItem{
		FoodItem: FoodItem{
			id:             'minecraft:chicken'
			food_points:    2
			saturation_mod: 1.2
		}
	}
}
