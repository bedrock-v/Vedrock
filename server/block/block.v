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

// Interactable is implemented by blocks with a behaviour on right click.
pub interface Interactable {
	// interact runs this block's right click behaviour at (x, y, z).
	// Returns whether it did anything, false means fall through, letting
	// the session layer treat the click as an ordinary placement attempt.
	interact(x int, y int, z int, click_face int, mut w TickWorld) bool
}

// Punchable is implemented by blocks with a behaviour on left click.
// the moment a player starts breaking it, separate from Interactable's
// right click behaviour and from anything that happens once the break
// actually completes.
pub interface Punchable {
	// punch runs this block's left click behaviour at (x, y, z). Unlike
	// interact() there's no fall through decision to make, punching a
	// block always proceeds to the normal start break animation regardless.
	punch(x int, y int, z int, click_face int, mut w TickWorld)
}

// Replaceable is implemented by blocks that get silently overwritten by a
// placement instead of blocking it.
pub interface Replaceable {
	replaceable() bool
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
