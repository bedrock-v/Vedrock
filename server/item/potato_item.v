module item

// PotatoItem is the class for 'minecraft:potato'.
pub struct PotatoItem {
	FoodItem
}

pub fn new_potato() PotatoItem {
	return PotatoItem{
		FoodItem: FoodItem{
			id:             'minecraft:potato'
			food_points:    1
			saturation_mod: 0.6
		}
	}
}
