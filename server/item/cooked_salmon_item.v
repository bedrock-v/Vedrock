module item

// CookedSalmonItem is the class for 'minecraft:cooked_salmon'.
pub struct CookedSalmonItem {
	FoodItem
}

pub fn new_cooked_salmon() CookedSalmonItem {
	return CookedSalmonItem{
		FoodItem: FoodItem{
			id:             'minecraft:cooked_salmon'
			food_points:    6
			saturation_mod: 9.6
		}
	}
}
