module item

// SwordItem is the base class for melee weapons. Tools never stack, so the
// max stack size is fixed at 1. damage feeds the combat calculation and
// durability bounds how many hits the sword survives. Concrete swords embed
// it, one class per sword.
pub struct SwordItem {
pub:
	id         string
	damage     f32
	durability int
}

pub fn (i SwordItem) identifier() string {
	return i.id
}

pub fn (i SwordItem) max_stack_size() int {
	return 1
}

pub fn (i SwordItem) attack_damage() f32 {
	return i.damage
}

pub fn (i SwordItem) nutrition() int {
	return 0
}

pub fn (i SwordItem) saturation() f32 {
	return 0
}

pub fn (i SwordItem) block_runtime_id() int {
	return 0
}
