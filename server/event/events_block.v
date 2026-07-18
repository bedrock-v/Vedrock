module event

import server.player

// BlockBreakData is dispatched before a block is broken. block_id is the block
// being removed. Cancelling it leaves the block in place.
pub struct BlockBreakData {
pub:
	x        int
	y        int
	z        int
	block_id int
pub mut:
	player player.View
}

// StartBreakData is dispatched the moment a player left clicks a block
// before any break timer starts, separate from BlockBreakData which only
// fires once the break actually completes.
pub struct StartBreakData {
pub:
	x    int
	y    int
	z    int
	face int
pub mut:
	player player.View
}

// BlockPlaceData is dispatched before a block is placed. block_id is the block
// being placed. Cancelling it stops the placement.
pub struct BlockPlaceData {
pub:
	x        int
	y        int
	z        int
	block_id int
pub mut:
	player player.View
}

// InteractData is dispatched when a player right clicks a block, before any
// placement is decided. Cancelling it stops the interaction
// and any place that would follow.
pub struct InteractData {
pub:
	x    int
	y    int
	z    int
	face int
pub mut:
	player player.View
}
