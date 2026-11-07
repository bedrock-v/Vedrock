module world

import server.world.chunk

// Column is a chunk a world holds along with what it was last sent as.
@[heap]
pub struct Column {
mut:
	chunk chunk.Chunk
	// encoded is the chunk as it is sent, shared by everyone it is sent to. A
	// block change empties it and the next loader to take the chunk makes it
	// again.
	encoded []u8
	// sub_chunks is how many sub chunks encoded holds which LevelChunk says.
	sub_chunks int
	// viewers are the loaders that have the chunk. A chunk nobody has is
	// dropped by the next sweep unless it is modified.
	viewers []&Loader
	// modified is set once a block in the chunk changes. Nothing can store
	// the chunk yet and the generator would make the old one again, so it is
	// kept until the world closes.
	modified bool
}

// spawn is where the world puts new players.
pub fn (tx &Tx) spawn() BlockPos {
	tx.ensure_live()
	return tx.world.spawn
}

// sweep_chunks drops every chunk no loader has and nothing changed.
fn (mut tx Tx) sweep_chunks() {
	mut unused := []u64{}
	for key, col in tx.world.chunks {
		if col.viewers.len == 0 && !col.modified {
			unused << key
		}
	}
	for key in unused {
		tx.world.chunks.delete(key)
	}
}

// column_key packs a position into one map key.
fn column_key(pos chunk.Pos) u64 {
	return u64(u32(pos.x)) << 32 | u64(u32(pos.z))
}
