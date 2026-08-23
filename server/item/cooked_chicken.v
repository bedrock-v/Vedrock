module item

// CookedChickenItem is the class for 'minecraft:cooked_chicken'.
pub struct CookedChickenItem {
	FoodItem
}

pub fn new_cooked_chicken() CookedChickenItem {
	return CookedChickenItem{
		FoodItem: FoodItem{
			id:             'minecraft:cooked_chicken'
			food_points:    6
			saturation_mod: 7.2
		}
	}
}
