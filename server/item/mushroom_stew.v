module item

// MushroomStewItem is the class for 'minecraft:mushroom_stew'.
pub struct MushroomStewItem {
	FoodItem
}

pub fn new_mushroom_stew() MushroomStewItem {
	return MushroomStewItem{
		FoodItem: FoodItem{
			id:             'minecraft:mushroom_stew'
			food_points:    6
			saturation_mod: 7.2
			stack_max:      1
		}
	}
}
