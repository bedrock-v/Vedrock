module item

// GlowBerriesItem is the class for 'minecraft:glow_berries'.
pub struct GlowBerriesItem {
	FoodItem
}

pub fn new_glow_berries() GlowBerriesItem {
	return GlowBerriesItem{
		FoodItem: FoodItem{
			id:             'minecraft:glow_berries'
			food_points:    2
			saturation_mod: 0.4
		}
	}
}
