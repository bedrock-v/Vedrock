module light

// LightKind selects which of the two light channels an operation acts on.
pub enum LightKind {
	block
	sky
}

// node is a single entry in the BFS queue - a position and the light level being
// propagated out from it.
struct Node {
	x     int
	y     int
	z     int
	level u8
}

// queue is a simple FIFO ring buffer of BFS nodes, mirroring dragonfly's
// lightQueue. A slice-backed ring keeps push/pop O(1) and avoids re-slicing.
struct Queue {
mut:
	nodes []Node
	head  int
	tail  int
	size  int
}

fn new_queue(capacity int) &Queue {
	cap := if capacity < 1 { 1 } else { capacity }
	return &Queue{
		nodes: []Node{len: cap}
	}
}

fn (mut q Queue) push(n Node) {
	if q.size == q.nodes.len {
		q.grow()
	}
	q.nodes[q.tail] = n
	q.tail = (q.tail + 1) % q.nodes.len
	q.size++
}

fn (mut q Queue) pop() ?Node {
	if q.size == 0 {
		return none
	}
	n := q.nodes[q.head]
	q.head = (q.head + 1) % q.nodes.len
	q.size--
	return n
}

fn (q &Queue) empty() bool {
	return q.size == 0
}

fn (mut q Queue) grow() {
	mut nodes := []Node{len: q.nodes.len * 2}
	for i in 0 .. q.size {
		nodes[i] = q.nodes[(q.head + i) % q.nodes.len]
	}
	q.head = 0
	q.tail = q.size
	q.nodes = nodes
}

// Region is the axis-aligned box the engine computes light for. Light is only
// stored and propagated inside the box; anything outside is treated as unlit and
// non-blocking so an emitter near the edge simply loses its light at the border.
pub struct Region {
pub:
	min_x int
	min_y int
	min_z int
	max_x int
	max_y int
	max_z int
}

// new_region normalizes the two corners so callers need not order them.
pub fn new_region(x1 int, y1 int, z1 int, x2 int, y2 int, z2 int) Region {
	return Region{
		min_x: if x1 < x2 { x1 } else { x2 }
		min_y: if y1 < y2 { y1 } else { y2 }
		min_z: if z1 < z2 { z1 } else { z2 }
		max_x: if x1 > x2 { x1 } else { x2 }
		max_y: if y1 > y2 { y1 } else { y2 }
		max_z: if z1 > z2 { z1 } else { z2 }
	}
}

// width, height, depth are the span of the region on each axis, inclusive.
pub fn (r Region) width() int {
	return r.max_x - r.min_x + 1
}

pub fn (r Region) height() int {
	return r.max_y - r.min_y + 1
}

pub fn (r Region) depth() int {
	return r.max_z - r.min_z + 1
}

// volume is the number of blocks the region covers, both corners inclusive.
pub fn (r Region) volume() int {
	return r.width() * r.height() * r.depth()
}

// contains reports whether an absolute coordinate falls inside the region.
pub fn (r Region) contains(x int, y int, z int) bool {
	return x >= r.min_x && x <= r.max_x && y >= r.min_y && y <= r.max_y && z >= r.min_z
		&& z <= r.max_z
}

// index maps an absolute coordinate to its flat slot in a per-block array. The
// caller must have checked contains first.
fn (r Region) index(x int, y int, z int) int {
	dx := x - r.min_x
	dy := y - r.min_y
	dz := z - r.min_z
	return (dy * r.depth() + dz) * r.width() + dx
}

// LightGrid holds the computed light levels for one Region. It carries both the
// block-light and sky-light channels so a single computation fills both. Levels
// are queried by absolute coordinate through light_at; a position outside the
// region reads as 0.
pub struct LightGrid {
pub:
	region Region
mut:
	block_light []u8
	sky_light   []u8
}

// light_at returns the light level of the given kind at an absolute coordinate,
// or 0 when the position lies outside the computed region.
pub fn (g &LightGrid) light_at(kind LightKind, x int, y int, z int) u8 {
	if !g.region.contains(x, y, z) {
		return 0
	}
	i := g.region.index(x, y, z)
	return match kind {
		.block { g.block_light[i] }
		.sky { g.sky_light[i] }
	}
}

// block_light_at and sky_light_at are convenience wrappers over light_at.
pub fn (g &LightGrid) block_light_at(x int, y int, z int) u8 {
	return g.light_at(.block, x, y, z)
}

pub fn (g &LightGrid) sky_light_at(x int, y int, z int) u8 {
	return g.light_at(.sky, x, y, z)
}

fn (mut g LightGrid) set(kind LightKind, x int, y int, z int, v u8) {
	i := g.region.index(x, y, z)
	match kind {
		.block { g.block_light[i] = v }
		.sky { g.sky_light[i] = v }
	}
}

fn (g &LightGrid) get(kind LightKind, x int, y int, z int) u8 {
	i := g.region.index(x, y, z)
	return match kind {
		.block { g.block_light[i] }
		.sky { g.sky_light[i] }
	}
}

// compute runs a full block-light and sky-light computation over the region,
// reading blocks from src. It returns none when the region exceeds max_volume so
// a bad query can't blow up memory - tile the region and merge instead.
pub fn compute(region Region, src BlockSource) ?&LightGrid {
	if region.volume() > max_volume {
		return none
	}
	mut g := &LightGrid{
		region:      region
		block_light: []u8{len: region.volume()}
		sky_light:   []u8{len: region.volume()}
	}
	g.compute_block_light(src)
	g.compute_sky_light(src)
	return g
}

// compute_block_light seeds the BFS with every emitter in the region and floods
// their light outward. Block light comes only from emitting blocks.
fn (mut g LightGrid) compute_block_light(src BlockSource) {
	mut q := new_queue(1024)
	r := g.region
	for y in r.min_y .. r.max_y + 1 {
		for z in r.min_z .. r.max_z + 1 {
			for x in r.min_x .. r.max_x + 1 {
				level := emission(src.get_block(x, y, z))
				if level > 0 {
					g.set(.block, x, y, z, level)
					q.push(Node{x, y, z, level})
				}
			}
		}
	}
	g.propagate(mut q, .block, src)
}

// compute_sky_light seeds full sky light (15) into every open-sky block - a
// block with nothing opaque above it inside the region - and floods it down and
// sideways. Descending straight down through air keeps the full 15; the flood
// then handles attenuation under overhangs and around corners.
fn (mut g LightGrid) compute_sky_light(src BlockSource) {
	mut q := new_queue(1024)
	r := g.region
	for z in r.min_z .. r.max_z + 1 {
		for x in r.min_x .. r.max_x + 1 {
			// Walk down the column from the top. While the sky is open, every
			// block gets full sky light and becomes a spread source.
			mut open := true
			for y := r.max_y; y >= r.min_y; y-- {
				if open && opaque(src.get_block(x, y, z)) {
					open = false
				}
				if open {
					g.set(.sky, x, y, z, max_light)
					q.push(Node{x, y, z, max_light})
				}
			}
		}
	}
	g.propagate(mut q, .sky, src)
}

// propagate drains the queue, spreading each node's light into its six
// neighbours. A neighbour is queued when the light reaching it - the source
// level minus 1 for the step minus the neighbour's filter - is brighter than
// what it already has. This is the standard BFS flood used by both inspirations.
fn (mut g LightGrid) propagate(mut q Queue, kind LightKind, src BlockSource) {
	for {
		n := q.pop() or { break }
		// Skip if a brighter value was written after this node was queued.
		if g.get(kind, n.x, n.y, n.z) > n.level {
			continue
		}
		g.spread(mut q, kind, src, n.level, n.x + 1, n.y, n.z)
		g.spread(mut q, kind, src, n.level, n.x - 1, n.y, n.z)
		g.spread(mut q, kind, src, n.level, n.x, n.y + 1, n.z)
		g.spread(mut q, kind, src, n.level, n.x, n.y - 1, n.z)
		g.spread(mut q, kind, src, n.level, n.x, n.y, n.z + 1)
		g.spread(mut q, kind, src, n.level, n.x, n.y, n.z - 1)
	}
}

fn (mut g LightGrid) spread(mut q Queue, kind LightKind, src BlockSource, from_level u8, x int, y int, z int) {
	if !g.region.contains(x, y, z) {
		return
	}
	// Cost to enter this block: 1 for the step plus its filtering. u16 math
	// avoids an underflow when the filter exceeds the source level.
	cost := u16(1) + u16(filter(src.get_block(x, y, z)))
	if u16(from_level) <= cost {
		return
	}
	new_level := u8(u16(from_level) - cost)
	if g.get(kind, x, y, z) >= new_level {
		return
	}
	g.set(kind, x, y, z, new_level)
	q.push(Node{x, y, z, new_level})
}

// add_light re-floods block light from a single position after an emitter is
// placed there. src must already report the new block. Only additive - use
// remove_light first if a brighter emitter was replaced by a dimmer one.
pub fn (mut g LightGrid) add_light(src BlockSource, x int, y int, z int) {
	if !g.region.contains(x, y, z) {
		return
	}
	level := emission(src.get_block(x, y, z))
	if level == 0 {
		return
	}
	if g.get(.block, x, y, z) >= level {
		return
	}
	mut q := new_queue(64)
	g.set(.block, x, y, z, level)
	q.push(Node{x, y, z, level})
	g.propagate(mut q, .block, src)
}

// remove_light clears block light originating from an emitter that was removed
// at the given position and re-propagates any surrounding light back into the
// hole. This is the classic two-pass BFS removal (dragonfly/PocketMine): first
// tear down every cell that was lit by the removed source, collecting brighter
// edge cells, then flood those edges back in. src must already report the block
// AFTER removal.
pub fn (mut g LightGrid) remove_light(src BlockSource, x int, y int, z int) {
	if !g.region.contains(x, y, z) {
		return
	}
	old := g.get(.block, x, y, z)
	if old == 0 {
		return
	}
	mut removal := new_queue(64)
	mut refill := new_queue(64)
	g.set(.block, x, y, z, 0)
	removal.push(Node{x, y, z, old})

	for {
		n := removal.pop() or { break }
		g.remove_neighbour(mut removal, mut refill, n.level, n.x + 1, n.y, n.z)
		g.remove_neighbour(mut removal, mut refill, n.level, n.x - 1, n.y, n.z)
		g.remove_neighbour(mut removal, mut refill, n.level, n.x, n.y + 1, n.z)
		g.remove_neighbour(mut removal, mut refill, n.level, n.x, n.y - 1, n.z)
		g.remove_neighbour(mut removal, mut refill, n.level, n.x, n.y, n.z + 1)
		g.remove_neighbour(mut removal, mut refill, n.level, n.x, n.y, n.z - 1)
	}

	// Any block that still emits (a nearby untouched emitter) must be re-seeded
	// so its light flows back into the cleared region.
	r := g.region
	for by in r.min_y .. r.max_y + 1 {
		for bz in r.min_z .. r.max_z + 1 {
			for bx in r.min_x .. r.max_x + 1 {
				e := emission(src.get_block(bx, by, bz))
				if e > 0 && g.get(.block, bx, by, bz) < e {
					g.set(.block, bx, by, bz, e)
					refill.push(Node{bx, by, bz, e})
				}
			}
		}
	}
	g.propagate(mut refill, .block, src)
}

fn (mut g LightGrid) remove_neighbour(mut removal Queue, mut refill Queue, from_level u8, x int, y int, z int) {
	if !g.region.contains(x, y, z) {
		return
	}
	cur := g.get(.block, x, y, z)
	if cur == 0 {
		return
	}
	if cur < from_level {
		// This cell was lit by the removed source - clear it and keep tearing down.
		g.set(.block, x, y, z, 0)
		removal.push(Node{x, y, z, cur})
	} else {
		// Brighter than what reached it, so it belongs to another source. Queue it
		// as a refill seed so its light flows back into the cleared cells.
		refill.push(Node{x, y, z, cur})
	}
}
