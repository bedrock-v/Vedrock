module item

// BakedPotatoItem is the class for 'minecraft:baked_potato'.
pub struct BakedPotatoItem {
	FoodItem
}

pub fn new_baked_potato() BakedPotatoItem {
	return BakedPotatoItem{
		FoodItem: FoodItem{
			id:             'minecraft:baked_potato'
			food_points:    5
			saturation_mod: 6.0
		}
	}
}
