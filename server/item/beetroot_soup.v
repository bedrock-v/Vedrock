module item

// BeetrootSoupItem is the class for 'minecraft:beetroot_soup'.
pub struct BeetrootSoupItem {
	FoodItem
}

pub fn new_beetroot_soup() BeetrootSoupItem {
	return BeetrootSoupItem{
		FoodItem: FoodItem{
			id:             'minecraft:beetroot_soup'
			food_points:    6
			saturation_mod: 7.2
			stack_max:      1
		}
	}
}
