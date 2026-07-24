module arena

// FakeWorld is an in-memory block grid standing in for a real world. It
// satisfies both BlockSource and BlockSink so a capture-then-restore round
// trip can be exercised without a LevelDB world or a live Hub.
struct FakeWorld {
mut:
	blocks map[string]int
	writes int
}

fn key(x int, y int, z int) string {
	return '${x}:${y}:${z}'
}

fn (mut w FakeWorld) get_block(x int, y int, z int) int {
	return w.blocks[key(x, y, z)] or { 0 }
}

fn (mut w FakeWorld) set_block_id(id int, x int, y int, z int) {
	w.blocks[key(x, y, z)] = id
	w.writes++
}

fn test_capture_then_restore_round_trip() {
	mut w := &FakeWorld{}
	// stamp a distinct id at every cell so a mixed-up order would show up.
	for x in 0 .. 3 {
		for y in 0 .. 3 {
			for z in 0 .. 3 {
				w.blocks[key(x, y, z)] = x * 100 + y * 10 + z
			}
		}
	}
	snap := capture(mut w, new_box(0, 0, 0, 2, 2, 2))!
	assert snap.len() == 27

	// overwrite the whole region, then restore it back.
	for x in 0 .. 3 {
		for y in 0 .. 3 {
			for z in 0 .. 3 {
				w.blocks[key(x, y, z)] = -1
			}
		}
	}
	snap.restore(mut w)
	for x in 0 .. 3 {
		for y in 0 .. 3 {
			for z in 0 .. 3 {
				assert w.get_block(x, y, z) == x * 100 + y * 10 + z
			}
		}
	}
	assert w.writes == 27
}

fn test_box_normalizes_corners() {
	b := new_box(5, 9, 8, 1, 2, 3)
	assert b.min_x == 1 && b.min_y == 2 && b.min_z == 3
	assert b.max_x == 5 && b.max_y == 9 && b.max_z == 8
	assert b.volume() == 5 * 8 * 6
}

fn test_single_block_box() {
	mut w := &FakeWorld{}
	w.blocks[key(10, 20, 30)] = 42
	snap := capture(mut w, new_box(10, 20, 30, 10, 20, 30))!
	assert snap.len() == 1
	w.blocks[key(10, 20, 30)] = 0
	snap.restore(mut w)
	assert w.get_block(10, 20, 30) == 42
}

fn test_capture_rejects_oversized_box() {
	mut w := &FakeWorld{}
	// one axis alone past the cap guarantees volume > max_volume.
	if _ := capture(mut w, new_box(0, 0, 0, max_volume + 1, 0, 0)) {
		assert false, 'expected oversized box to be rejected'
	}
}
