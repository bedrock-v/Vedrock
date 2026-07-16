module item

// MelonSliceItem is the class for 'minecraft:melon_slice'.
pub struct MelonSliceItem {
	FoodItem
}

pub fn new_melon_slice() MelonSliceItem {
	return MelonSliceItem{
		FoodItem: FoodItem{
			id:             'minecraft:melon_slice'
			food_points:    2
			saturation_mod: 1.2
		}
	}
}
