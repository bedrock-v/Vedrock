module item

// BlockItem is the class for items that place a block when used against a
// face. It carries the block runtime id the session should set in the world.
pub struct BlockItem {
pub:
	id               string
	block_runtime_id int
}

pub fn (i BlockItem) identifier() string {
	return i.id
}

pub fn (i BlockItem) max_stack_size() int {
	return 64
}

// placed_block_runtime_id is the block the session places on use.
pub fn (i BlockItem) placed_block_runtime_id() int {
	return i.block_runtime_id
}
