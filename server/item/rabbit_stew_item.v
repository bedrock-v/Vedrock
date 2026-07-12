module item

// RabbitStewItem is the class for 'minecraft:rabbit_stew'.
pub struct RabbitStewItem {
	FoodItem
}

pub fn new_rabbit_stew() RabbitStewItem {
	return RabbitStewItem{
		FoodItem: FoodItem{
			id:             'minecraft:rabbit_stew'
			food_points:    10
			saturation_mod: 12.0
			stack_max:      1
		}
	}
}
