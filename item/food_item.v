module item

// FoodItem is the class for edibles. nutrition is the number of hunger points
// restored on eat, saturation the saturation modifier.
pub struct FoodItem {
pub:
	id         string
	nutrition  int
	saturation f32
}

pub fn (i FoodItem) identifier() string {
	return i.id
}

pub fn (i FoodItem) max_stack_size() int {
	return 64
}

// restores returns the hunger points this food gives on eat.
pub fn (i FoodItem) restores() int {
	return i.nutrition
}
