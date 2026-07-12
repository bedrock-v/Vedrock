module block

// Block is the behaviour contract every block class implements. Concrete
// classes (one struct per block family) live in their own files and are
// registered in the Registry so the session layer can look them up by their
// runtime id or namespaced identifier (e.g. 'minecraft:stone').
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

// SimpleBlock is the fallback class for blocks that carry no special
// behaviour beyond a hardness value. Anything not explicitly modelled falls
// back to a SimpleBlock.
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
