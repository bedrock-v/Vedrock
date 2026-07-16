module item

// MuttonItem is the class for 'minecraft:mutton'.
pub struct MuttonItem {
	FoodItem
}

pub fn new_mutton() MuttonItem {
	return MuttonItem{
		FoodItem: FoodItem{
			id:             'minecraft:mutton'
			food_points:    2
			saturation_mod: 1.2
		}
	}
}
