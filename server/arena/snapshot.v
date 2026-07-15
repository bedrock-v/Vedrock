module arena

// BlockSource reads block network ids from a world by absolute coordinates.
// Hub satisfies it; tests use an in-memory grid.
pub interface BlockSource {
mut:
	get_block(x int, y int, z int) int
}

// BlockSink writes a block by network id and broadcasts the change to viewers.
// Restore goes through this so a reset looks identical to normal block edits.
pub interface BlockSink {
mut:
	set_block_id(id int, x int, y int, z int)
}

// max_volume caps how many blocks a single snapshot may capture so a bad
// min/max box can't allocate unbounded memory. 256*256*256 is generous for
// a minigame arena while still bounded.
pub const max_volume = 256 * 256 * 256

// Box is an axis-aligned block region, normalized so min <= max on every axis.
pub struct Box {
pub:
	min_x int
	min_y int
	min_z int
	max_x int
	max_y int
	max_z int
}

// new_box normalizes the two corners so the caller need not order them.
pub fn new_box(x1 int, y1 int, z1 int, x2 int, y2 int, z2 int) Box {
	return Box{
		min_x: if x1 < x2 { x1 } else { x2 }
		min_y: if y1 < y2 { y1 } else { y2 }
		min_z: if z1 < z2 { z1 } else { z2 }
		max_x: if x1 > x2 { x1 } else { x2 }
		max_y: if y1 > y2 { y1 } else { y2 }
		max_z: if z1 > z2 { z1 } else { z2 }
	}
}

// volume is the number of blocks the box covers (inclusive on both corners).
// Computed in i64 so a huge box can't overflow int32 and slip past the cap.
pub fn (b Box) volume() i64 {
	return i64(b.max_x - b.min_x + 1) * i64(b.max_y - b.min_y + 1) * i64(b.max_z - b.min_z + 1)
}

// Snapshot holds the block ids of a Box captured at some point in time. It is
// a flat array so a full restore is a single linear pass. Memory cost is
// 4 bytes per block - a 64^3 arena is ~1 MB.
pub struct Snapshot {
pub:
	box Box
mut:
	ids []int
}

// capture reads every block in box from src into a fresh Snapshot. Returns an
// error if the box exceeds max_volume so a runaway box can't exhaust memory.
pub fn capture(mut src BlockSource, box Box) !&Snapshot {
	if box.volume() > max_volume {
		return error('arena: box volume ${box.volume()} exceeds cap ${max_volume}')
	}
	mut ids := []int{cap: int(box.volume())}
	for y := box.min_y; y <= box.max_y; y++ {
		for x := box.min_x; x <= box.max_x; x++ {
			for z := box.min_z; z <= box.max_z; z++ {
				ids << src.get_block(x, y, z)
			}
		}
	}
	return &Snapshot{
		box: box
		ids: ids
	}
}

// restore writes every captured block back through sink in the same order it
// was captured, so viewers see the arena reset to its saved state.
pub fn (s &Snapshot) restore(mut sink BlockSink) {
	mut i := 0
	for y := s.box.min_y; y <= s.box.max_y; y++ {
		for x := s.box.min_x; x <= s.box.max_x; x++ {
			for z := s.box.min_z; z <= s.box.max_z; z++ {
				sink.set_block_id(s.ids[i], x, y, z)
				i++
			}
		}
	}
}

// len is the number of blocks stored in the snapshot.
pub fn (s &Snapshot) len() int {
	return s.ids.len
}
