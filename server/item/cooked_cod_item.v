module item

// CookedCodItem is the class for 'minecraft:cooked_cod'.
pub struct CookedCodItem {
	FoodItem
}

pub fn new_cooked_cod() CookedCodItem {
	return CookedCodItem{
		FoodItem: FoodItem{
			id:             'minecraft:cooked_cod'
			food_points:    5
			saturation_mod: 6.0
		}
	}
}
