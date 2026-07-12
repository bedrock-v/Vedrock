module item

// PumpkinPieItem is the class for 'minecraft:pumpkin_pie'.
pub struct PumpkinPieItem {
	FoodItem
}

pub fn new_pumpkin_pie() PumpkinPieItem {
	return PumpkinPieItem{
		FoodItem: FoodItem{
			id:             'minecraft:pumpkin_pie'
			food_points:    8
			saturation_mod: 4.8
		}
	}
}
