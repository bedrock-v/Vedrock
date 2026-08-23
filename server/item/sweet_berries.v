module item

// SweetBerriesItem is the class for 'minecraft:sweet_berries'.
pub struct SweetBerriesItem {
	FoodItem
}

pub fn new_sweet_berries() SweetBerriesItem {
	return SweetBerriesItem{
		FoodItem: FoodItem{
			id:             'minecraft:sweet_berries'
			food_points:    2
			saturation_mod: 0.4
		}
	}
}
