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
}

// spawn is where the world puts new players.
pub fn (tx &Tx) spawn() BlockPos {
	tx.ensure_live()
	return tx.world.spawn
}

// encoded_chunk is the chunk at a position as it is sent, generating the chunk
// when the world doesn't have it yet.
//
// Every caller gets the same bytes, so they must not be written to.
pub fn (mut tx Tx) encoded_chunk(pos chunk.Pos) []u8 {
	tx.ensure_live()
	mut col := tx.column(pos)
	if col.encoded.len == 0 {
		col.encoded = col.chunk.encode()
	}
	return col.encoded
}

// column is the chunk at a position, generated first when the world doesn't
// have it.
fn (mut tx Tx) column(pos chunk.Pos) &Column {
	key := column_key(pos)
	if col := tx.world.chunks[key] {
		return col
	}
	mut c := chunk.new()
	tx.world.generator.generate_chunk(pos, mut c)
	col := &Column{
		chunk: c
	}
	tx.world.chunks[key] = col
	return col
}

// column_key packs a position into one map key.
fn column_key(pos chunk.Pos) u64 {
	return u64(u32(pos.x)) << 32 | u64(u32(pos.z))
}
