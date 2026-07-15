module item

// Remaining edible items that only need nutrition/saturation data for now.
fn tail_food_items() []Item {
	return [
		Item(FoodItem{
			id:             'minecraft:rabbit'
			food_points:    3
			saturation_mod: 1.8
		}),
		Item(FoodItem{
			id:             'minecraft:cooked_rabbit'
			food_points:    5
			saturation_mod: 6.0
		}),
		Item(FoodItem{
			id:             'minecraft:suspicious_stew'
			food_points:    6
			saturation_mod: 7.2
			stack_max:      1
		}),
		Item(FoodItem{
			id:             'minecraft:chorus_fruit'
			food_points:    4
			saturation_mod: 2.4
		}),
		Item(FoodItem{
			id:             'minecraft:pufferfish'
			food_points:    1
			saturation_mod: 0.2
		}),
		Item(FoodItem{
			id:             'minecraft:tropical_fish'
			food_points:    1
			saturation_mod: 0.2
		}),
		Item(FoodItem{
			id:             'minecraft:rotten_flesh'
			food_points:    4
			saturation_mod: 0.8
		}),
		Item(FoodItem{
			id:             'minecraft:spider_eye'
			food_points:    2
			saturation_mod: 3.2
		}),
		Item(FoodItem{
			id:             'minecraft:enchanted_golden_apple'
			food_points:    4
			saturation_mod: 2.4
		}),
	]
}
