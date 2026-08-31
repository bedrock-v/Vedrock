module item

// SalmonItem is the class for 'minecraft:salmon'.
pub struct SalmonItem {
	FoodItem
}

pub fn new_salmon() SalmonItem {
	return SalmonItem{
		FoodItem: FoodItem{
			id:             'minecraft:salmon'
			food_points:    2
			saturation_mod: 0.4
		}
	}
}
