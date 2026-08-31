module item

// FoodItem is the base class for edibles. food_points is the number of
// hunger points restored on eat, saturation_mod the saturation modifier.
// Concrete foods embed it, one class per food.
pub struct FoodItem {
pub:
	id             string
	food_points    int
	saturation_mod f32
	stack_max      int = 64
}

pub fn (i FoodItem) identifier() string {
	return i.id
}

pub fn (i FoodItem) max_stack_size() int {
	return i.stack_max
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

pub fn (i FoodItem) durability() int {
	return 0
}

pub fn (i FoodItem) mining_speed() f32 {
	return 1.0
}

pub fn (i FoodItem) armor_points() int {
	return 0
}
