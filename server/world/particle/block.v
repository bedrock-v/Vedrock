module particle

import protocol.current as proto

// BlockBreak is the burst of block fragments shown when a block is broken. The
// runtime id decides which texture the fragments use.
pub struct BlockBreak {
pub:
	block_runtime_id int
}

pub fn (p BlockBreak) event_id() int {
	return proto.level_event_particles_destroy_block
}

pub fn (p BlockBreak) data() int {
	return p.block_runtime_id
}

// PunchBlock is the small puff of fragments shown while a block is being
// mined, coming off the face that is being hit.
pub struct PunchBlock {
pub:
	block_runtime_id int
	face             int
}

pub fn (p PunchBlock) event_id() int {
	return proto.level_event_particles_punch_block
}

pub fn (p PunchBlock) data() int {
	return p.block_runtime_id | int(u32(p.face) << 24)
}

// Custom is a particle the client renders for a level event the server has no
// dedicated type for yet. It exists so a caller is never forced back to
// building level event packets by hand.
pub struct Custom {
pub:
	id      int
	payload int
}

pub fn (p Custom) event_id() int {
	return p.id
}

pub fn (p Custom) data() int {
	return p.payload
}
