module block

// UnbreakableBlock is the class for blocks survival players can never
// destroy (bedrock, barriers). Creative mode bypasses the check in the
// session layer.
pub struct UnbreakableBlock {
pub:
	id            string
	block_runtime int
}

pub fn (b UnbreakableBlock) identifier() string {
	return b.id
}

pub fn (b UnbreakableBlock) runtime_id() int {
	return b.block_runtime
}

pub fn (b UnbreakableBlock) hardness() f32 {
	return -1.0
}

pub fn (b UnbreakableBlock) breakable() bool {
	return false
}
