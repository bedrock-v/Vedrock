module item

// BlockItem is the base class for items that place a block when used against
// a face. It carries the block runtime id the session should set in the
// world. Concrete block items embed it, one class per block item.
pub struct BlockItem {
pub:
	id            string
	block_runtime int
}

pub fn (i BlockItem) identifier() string {
	return i.id
}

pub fn (i BlockItem) max_stack_size() int {
	return 64
}

pub fn (i BlockItem) attack_damage() f32 {
	return 0
}

pub fn (i BlockItem) nutrition() int {
	return 0
}

pub fn (i BlockItem) saturation() f32 {
	return 0
}

pub fn (i BlockItem) block_runtime_id() int {
	return i.block_runtime
}

pub fn (i BlockItem) durability() int {
	return 0
}

pub fn (i BlockItem) mining_speed() f32 {
	return 1.0
}

pub fn (i BlockItem) armor_points() int {
	return 0
}
