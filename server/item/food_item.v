module item

// FoodItem is the base class for edibles. food_points is the number of
// hunger points restored on eat, saturation_mod the saturation modifier.
// Concrete foods embed it, one class per food.
pub struct FoodItem {
pub:
	id             string
	food_points    int
	saturation_mod f32
}

pub fn (i FoodItem) identifier() string {
	return i.id
}

pub fn (i FoodItem) max_stack_size() int {
	return 64
}

pub fn (i FoodItem) attack_damage() f32 {
	return 0
}

pub fn (i FoodItem) nutrition() int {
	return i.food_points
}

pub fn (i FoodItem) saturation() f32 {
	return i.saturation_mod
}

pub fn (i FoodItem) block_runtime_id() int {
	return 0
}

// AppleItem is the class for 'minecraft:apple'.
pub struct AppleItem {
	FoodItem
}

pub fn new_apple() AppleItem {
	return AppleItem{
		FoodItem: FoodItem{
			id:             'minecraft:apple'
			food_points:    4
			saturation_mod: 2.4
		}
	}
}

// BreadItem is the class for 'minecraft:bread'.
pub struct BreadItem {
	FoodItem
}

pub fn new_bread() BreadItem {
	return BreadItem{
		FoodItem: FoodItem{
			id:             'minecraft:bread'
			food_points:    5
			saturation_mod: 6.0
		}
	}
}

// CookedBeefItem is the class for 'minecraft:cooked_beef'.
pub struct CookedBeefItem {
	FoodItem
}

pub fn new_cooked_beef() CookedBeefItem {
	return CookedBeefItem{
		FoodItem: FoodItem{
			id:             'minecraft:cooked_beef'
			food_points:    8
			saturation_mod: 12.8
		}
	}
}

// GoldenAppleItem is the class for 'minecraft:golden_apple'.
pub struct GoldenAppleItem {
	FoodItem
}

pub fn new_golden_apple() GoldenAppleItem {
	return GoldenAppleItem{
		FoodItem: FoodItem{
			id:             'minecraft:golden_apple'
			food_points:    4
			saturation_mod: 9.6
		}
	}
}

// CarrotItem is the class for 'minecraft:carrot'.
pub struct CarrotItem {
	FoodItem
}

pub fn new_carrot() CarrotItem {
	return CarrotItem{
		FoodItem: FoodItem{
			id:             'minecraft:carrot'
			food_points:    3
			saturation_mod: 3.6
		}
	}
}

// CookedChickenItem is the class for 'minecraft:cooked_chicken'.
pub struct CookedChickenItem {
	FoodItem
}

pub fn new_cooked_chicken() CookedChickenItem {
	return CookedChickenItem{
		FoodItem: FoodItem{
			id:             'minecraft:cooked_chicken'
			food_points:    6
			saturation_mod: 7.2
		}
	}
}
