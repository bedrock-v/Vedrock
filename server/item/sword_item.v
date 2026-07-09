module item

// SwordItem is the class for melee weapons. Tools never stack, so the max
// stack size is fixed at 1. attack_damage feeds the combat calculation and
// durability bounds how many hits the sword survives.
pub struct SwordItem {
pub:
	id            string
	attack_damage int
	durability    int
}

pub fn (i SwordItem) identifier() string {
	return i.id
}

pub fn (i SwordItem) max_stack_size() int {
	return 1
}

// damage is the melee damage this sword deals on hit.
pub fn (i SwordItem) damage() int {
	return i.attack_damage
}
