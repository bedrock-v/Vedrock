module world

import server.world.chunk

// Column is a chunk a world holds along with what it was last sent as.
@[heap]
pub struct Column {
mut:
	chunk chunk.Chunk
	// encoded is the chunk as it is sent, made when it is first asked for and
	// shared by everyone it is sent to. Empty until then.
	encoded []u8
	// sub_chunks is how many sub chunks encoded holds which LevelChunk says.
	sub_chunks int
	// viewers are the loaders that have the chunk. A chunk nobody has is
	// dropped by the next sweep.
	viewers []&Loader
}

// spawn is where the world puts new players.
pub fn (tx &Tx) spawn() BlockPos {
	tx.ensure_live()
	return tx.world.spawn
}

// sweep_chunks drops every chunk no loader has.
fn (mut tx Tx) sweep_chunks() {
	mut unused := []u64{}
	for key, col in tx.world.chunks {
		if col.viewers.len == 0 {
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
