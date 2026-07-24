module item

// CookedBeefItem is the class for 'minecraft:cooked_beef'.
pub struct CookedBeefItem {
	FoodItem
}

pub fn new_cooked_beef() CookedBeefItem {
	return CookedBeefItem{
		FoodItem: FoodItem{
			id:             'minecraft:cooked_beef'
			food_points:    8
			saturation_mod: 12.8
		}
	}
}
