module item

// CookedPorkchopItem is the class for 'minecraft:cooked_porkchop'.
pub struct CookedPorkchopItem {
	FoodItem
}

pub fn new_cooked_porkchop() CookedPorkchopItem {
	return CookedPorkchopItem{
		FoodItem: FoodItem{
			id:             'minecraft:cooked_porkchop'
			food_points:    8
			saturation_mod: 12.8
		}
	}
}
