module block

// Block is the behaviour contract every block class implements. Every block
// is its own class built on a family base struct (SimpleBlock,
// UnbreakableBlock) and registered in the Registry so the session layer can
// look it up by its runtime id or namespaced identifier.
pub interface Block {
	// identifier returns the namespaced block id.
	identifier() string
	// runtime_id is the network runtime id sent on the wire.
	runtime_id() int
	// hardness is how long the block resists breaking, in vanilla units.
	hardness() f32
	// breakable reports whether survival players can destroy this block.
	breakable() bool
}

// SimpleBlock is the base class for blocks that carry no special behaviour
// beyond a hardness value. Concrete blocks embed it and fill in their
// identity; anything unregistered behaves like a default SimpleBlock.
pub struct SimpleBlock {
pub:
	id             string
	block_runtime  int
	break_hardness f32 = 1.0
}

pub fn (b SimpleBlock) identifier() string {
	return b.id
}

pub fn (b SimpleBlock) runtime_id() int {
	return b.block_runtime
}

pub fn (b SimpleBlock) hardness() f32 {
	return b.break_hardness
}

pub fn (b SimpleBlock) breakable() bool {
	return true
}
