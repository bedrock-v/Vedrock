module world

import math
import server.world.chunk

// Loader is what one viewer sees of a world: the chunks within a radius of
// where it is. It hands them out a few at a time, nearest first and views each
// until it falls out of the radius.
//
// Only the world's thread touches it through the Tx its methods are given.
@[heap]
pub struct Loader {
mut:
	radius int
	// radius_changed is set when the radius changes and cleared once it has
	// been reported. The viewer is told the radius it now has.
	radius_changed bool
	centre         ?chunk.Pos
	// loaded holds the chunks handed out so far by column_key.
	loaded map[u64]chunk.Pos
	// queue is what is left to hand out, nearest first.
	queue []chunk.Pos
}

// LoadedChunk is a chunk ready to send. Its bytes are shared and must
// not be written to.
pub struct LoadedChunk {
pub:
	pos     chunk.Pos
	encoded []u8
}

// new_loader is a loader that sees radius chunks around it. It sees nothing
// until it is moved somewhere.
pub fn new_loader(radius int) &Loader {
	return &Loader{
		radius: radius
		loaded: map[u64]chunk.Pos{}
	}
}

// radius is how many chunks around it the loader sees.
pub fn (l &Loader) radius() int {
	return l.radius
}

// take_radius_change reports a radius that changed since it was last asked.
pub fn (mut l Loader) take_radius_change() ?int {
	if !l.radius_changed {
		return none
	}
	l.radius_changed = false
	return l.radius
}

// move centres the loader on a block position and reports whether that put it
// in another chunk. Chunks that fell out of the radius stop being viewed.
pub fn (mut l Loader) move(mut tx Tx, x f32, z f32) bool {
	tx.ensure_live()
	centre := chunk.Pos{int(math.floor(x)) >> 4, int(math.floor(z)) >> 4}
	if current := l.centre {
		if current == centre {
			return false
		}
	}
	l.centre = centre
	l.refresh(mut tx)
	return true
}

// change_radius makes the loader see radius chunks around it.
pub fn (mut l Loader) change_radius(mut tx Tx, radius int) {
	tx.ensure_live()
	if radius == l.radius {
		return
	}
	l.radius = radius
	l.radius_changed = true
	l.refresh(mut tx)
}

// load hands out up to n chunks the loader hasn't yet, nearest first,
// generating any the world doesn't have.
pub fn (mut l Loader) load(mut tx Tx, n int) []LoadedChunk {
	tx.ensure_live()
	mut out := []LoadedChunk{}
	for out.len < n && l.queue.len > 0 {
		pos := l.queue[0]
		l.queue.delete(0)
		key := column_key(pos)
		if key in l.loaded {
			continue
		}
		mut col := tx.column(pos)
		col.viewers << l
		l.loaded[key] = pos
		out << LoadedChunk{
			pos:     pos
			encoded: tx.encoded_chunk(pos)
		}
	}
	return out
}

// close stops the loader viewing anything. The chunks it viewed stay in the
// world until the next sweep finds nobody viewing them.
pub fn (mut l Loader) close(mut tx Tx) {
	tx.ensure_live()
	for key, _ in l.loaded {
		l.stop_viewing(mut tx, key)
	}
	l.loaded.clear()
	l.queue.clear()
	l.centre = none
}

// refresh stops viewing what is now out of the radius and queues what came
// into it.
fn (mut l Loader) refresh(mut tx Tx) {
	centre := l.centre or { return }
	mut gone := []u64{}
	for key, pos in l.loaded {
		if !within(centre, pos, l.radius) {
			gone << key
		}
	}
	for key in gone {
		l.stop_viewing(mut tx, key)
		l.loaded.delete(key)
	}
	l.queue.clear()
	for offset in ring_offsets(l.radius) {
		pos := chunk.Pos{centre.x + offset.x, centre.z + offset.z}
		if column_key(pos) !in l.loaded {
			l.queue << pos
		}
	}
}

fn (mut l Loader) stop_viewing(mut tx Tx, key u64) {
	mut col := tx.world.chunks[key] or { return }
	for i, v in col.viewers {
		if voidptr(v) == voidptr(l) {
			col.viewers.delete(i)
			break
		}
	}
}

fn within(centre chunk.Pos, pos chunk.Pos, radius int) bool {
	dx := pos.x - centre.x
	dz := pos.z - centre.z
	return dx * dx + dz * dz <= radius * radius
}

// ring_offsets are the chunk offsets within radius of a centre, nearest first.
fn ring_offsets(radius int) []chunk.Pos {
	mut offsets := []chunk.Pos{}
	for x in -radius .. radius + 1 {
		for z in -radius .. radius + 1 {
			if x * x + z * z <= radius * radius {
				offsets << chunk.Pos{x, z}
			}
		}
	}
	offsets.sort_with_compare(fn (a &chunk.Pos, b &chunk.Pos) int {
		return (a.x * a.x + a.z * a.z) - (b.x * b.x + b.z * b.z)
	})
	return offsets
}
