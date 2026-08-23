module item

// PorkchopItem is the class for 'minecraft:porkchop'.
pub struct PorkchopItem {
	FoodItem
}

pub fn new_porkchop() PorkchopItem {
	return PorkchopItem{
		FoodItem: FoodItem{
			id:             'minecraft:porkchop'
			food_points:    3
			saturation_mod: 1.8
		}
	}
}
