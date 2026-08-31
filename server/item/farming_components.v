module item

// Non-block items of the farming family; the block items live in
// server/block/farming_components_item.v.

const bone_mealable_crops = ['minecraft:wheat', 'minecraft:carrots', 'minecraft:potatoes',
	'minecraft:beetroot']

// BoneMealItem is the class for 'minecraft:bone_meal'.
pub struct BoneMealItem {
	SimpleItem
}

pub fn (i BoneMealItem) use_on_block_result(block_name string, meta int) ?UseOnBlockResult {
	if block_name !in bone_mealable_crops {
		return none
	}
	return UseOnBlockResult{
		state_key:   'growth'
		state_delta: 1
	}
}

pub fn new_bone_meal_item() BoneMealItem {
	return BoneMealItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:bone_meal'
		}
	}
}

// WheatItem is the class for raw 'minecraft:wheat'.
pub struct WheatItem {
	SimpleItem
}

pub fn new_wheat() WheatItem {
	return WheatItem{
		SimpleItem: SimpleItem{
			id: 'minecraft:wheat'
		}
	}
}

pub fn (i WheatItem) use_on_block_result(block_name string, meta int) ?UseOnBlockResult {
	return compost_result(block_name)
}

// CookieItem is the class for 'minecraft:cookie'.
pub struct CookieItem {
	FoodItem
}

pub fn new_cookie() CookieItem {
	return CookieItem{
		FoodItem: FoodItem{
			id:             'minecraft:cookie'
			food_points:    2
			saturation_mod: 0.4
		}
	}
}

// GoldenCarrotItem is the class for 'minecraft:golden_carrot'.
pub struct GoldenCarrotItem {
	FoodItem
}

pub fn new_golden_carrot() GoldenCarrotItem {
	return GoldenCarrotItem{
		FoodItem: FoodItem{
			id:             'minecraft:golden_carrot'
			food_points:    6
			saturation_mod: 14.4
		}
	}
}

// PoisonousPotatoItem is the class for 'minecraft:poisonous_potato'.
pub struct PoisonousPotatoItem {
	FoodItem
}

pub fn new_poisonous_potato() PoisonousPotatoItem {
	return PoisonousPotatoItem{
		FoodItem: FoodItem{
			id:             'minecraft:poisonous_potato'
			food_points:    2
			saturation_mod: 1.2
		}
	}
}

pub fn farming_items() []Item {
	mut result := []Item{}
	result << Item(new_bone_meal_item())
	result << new_wheat()
	result << new_cookie()
	result << new_golden_carrot()
	result << new_poisonous_potato()
	return result
}
