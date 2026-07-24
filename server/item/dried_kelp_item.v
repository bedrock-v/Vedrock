module item

// DriedKelpItem is the class for 'minecraft:dried_kelp'.
pub struct DriedKelpItem {
	FoodItem
}

pub fn new_dried_kelp() DriedKelpItem {
	return DriedKelpItem{
		FoodItem: FoodItem{
			id:             'minecraft:dried_kelp'
			food_points:    1
			saturation_mod: 0.6
		}
	}
}
