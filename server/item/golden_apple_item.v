module item

// GoldenAppleItem is the class for 'minecraft:golden_apple'.
pub struct GoldenAppleItem {
	FoodItem
}

pub fn new_golden_apple() GoldenAppleItem {
	return GoldenAppleItem{
		FoodItem: FoodItem{
			id:             'minecraft:golden_apple'
			food_points:    4
			saturation_mod: 9.6
		}
	}
}
