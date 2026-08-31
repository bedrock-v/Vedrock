module item

// CodItem is the class for 'minecraft:cod'.
pub struct CodItem {
	FoodItem
}

pub fn new_cod() CodItem {
	return CodItem{
		FoodItem: FoodItem{
			id:             'minecraft:cod'
			food_points:    2
			saturation_mod: 0.4
		}
	}
}
