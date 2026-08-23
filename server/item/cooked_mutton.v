module item

// CookedMuttonItem is the class for 'minecraft:cooked_mutton'.
pub struct CookedMuttonItem {
	FoodItem
}

pub fn new_cooked_mutton() CookedMuttonItem {
	return CookedMuttonItem{
		FoodItem: FoodItem{
			id:             'minecraft:cooked_mutton'
			food_points:    6
			saturation_mod: 9.6
		}
	}
}
