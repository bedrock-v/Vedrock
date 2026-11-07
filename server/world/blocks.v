module world

import server.world.chunk

// max_block_updates is how many changed blocks a loader holds before it sends
// the chunks they are in again instead.
const max_block_updates = 4096

// BlockUpdate is a block that changed in a chunk a loader has, ready to send:
// its position, its layer and its network ID.
pub struct BlockUpdate {
pub:
	pos   BlockPos
	layer int
	hash  u32
}

// ChunkChanges are the changed blocks of one chunk a loader has and not sent
// yet: the latest block for each position and layer by its key in the chunk.
@[heap]
struct ChunkChanges {
	pos chunk.Pos
mut:
	blocks map[u32]u32
}

// block is the block at a position on a layer, or none when its chunk isn't
// loaded.
pub fn (tx &Tx) block(pos BlockPos, layer int) ?u32 {
	tx.ensure_live()
	if !in_height(pos) || layer !in [0, 1] {
		return none
	}
	col := tx.world.chunks[column_key(chunk_of(pos))] or { return none }
	return col.chunk.block(pos.x & 15, pos.y, pos.z & 15, layer)
}

// set_block puts a block at a position on a layer and tells everyone who has
// the chunk. Setting the block that is already there does nothing.
//
// It fails for a position above or below the world, a layer other than 0 or 1,
// an ID the world has no block for and a chunk the world doesn't hold. A chunk
// is never generated here: that happens on the workers and the world doesn't
// wait for them.
pub fn (mut tx Tx) set_block(pos BlockPos, layer int, id u32) ! {
	tx.ensure_live()
	if !in_height(pos) {
		return error('y ${pos.y} is outside the world, ${chunk.min_y} to ${chunk.max_y}')
	}
	if layer !in [0, 1] {
		return error('a block is on layer 0 or 1, not ${layer}')
	}
	if id >= u32(tx.world.blocks.len()) {
		return error('block ID ${id} is not in the registry')
	}
	at := chunk_of(pos)
	mut col := tx.world.chunks[column_key(at)] or {
		return error('chunk ${at.x} ${at.z} is not loaded')
	}
	x, z := pos.x & 15, pos.z & 15
	if col.chunk.block(x, pos.y, z, layer) == id {
		return
	}
	col.chunk.set_block(x, pos.y, z, layer, id)
	col.modified = true
	// Made again, compacted, by the next loader that takes the chunk.
	col.encoded = []u8{}
	for viewer in col.viewers.clone() {
		mut l := unsafe { viewer }
		l.block_changed(mut tx, at, x, pos.y, z, layer, id)
	}
}

// block_changed holds a change to a chunk the loader has until it is taken.
fn (mut l Loader) block_changed(mut tx Tx, at chunk.Pos, x int, y int, z int, layer int, id u32) {
	key := column_key(at)
	mut changes := l.updates[key] or {
		fresh := &ChunkChanges{
			pos:    at
			blocks: map[u32]u32{}
		}
		l.updates[key] = fresh
		fresh
	}
	local := u32(x << 14 | z << 10 | (y - chunk.min_y) << 1 | layer)
	if local !in changes.blocks {
		l.update_count++
	}
	changes.blocks[local] = id
	if l.update_count > max_block_updates {
		l.resend_changed(mut tx)
	}
}

// resend_changed puts every chunk with changes back first in line.
// It goes out again whole with them.
fn (mut l Loader) resend_changed(mut tx Tx) {
	mut again := []chunk.Pos{}
	for _, changes in l.updates {
		again << changes.pos
	}
	// Stopping drops the chunk's changes, it can't run over the map.
	for pos in again {
		key := column_key(pos)
		l.stop_viewing(mut tx, key)
		l.loaded.delete(key)
	}
	l.queue.prepend(again)
}

// take_block_updates hands out the changes held since the last call.
pub fn (mut l Loader) take_block_updates(tx &Tx) []BlockUpdate {
	tx.ensure_live()
	mut out := []BlockUpdate{cap: l.update_count}
	for _, changes in l.updates {
		for local, id in changes.blocks {
			out << BlockUpdate{
				pos:   BlockPos{
					x: changes.pos.x << 4 | int(local >> 14)
					y: int(local >> 1 & 0x1ff) + chunk.min_y
					z: changes.pos.z << 4 | int(local >> 10 & 15)
				}
				layer: int(local & 1)
				hash:  tx.world.blocks.hash(id)
			}
		}
	}
	l.updates.clear()
	l.update_count = 0
	return out
}

fn in_height(pos BlockPos) bool {
	return pos.y >= chunk.min_y && pos.y <= chunk.max_y
}

fn chunk_of(pos BlockPos) chunk.Pos {
	return chunk.Pos{pos.x >> 4, pos.z >> 4}
}
