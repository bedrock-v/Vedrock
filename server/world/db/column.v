module db

import bedrock_v.nbt

// A column is everything this server has written inside one 16x16 chunk
// footprint, over the full world height: block overrides and block entities
// together. It is the unit the store reads and writes and the unit resident
// memory is accounted in which is why positions inside one are packed
// relative to it rather than stored absolutely.
@[heap]
pub struct Column {
pub mut:
	blocks         map[i64]int
	block_entities map[i64]nbt.Compound
	// dirty marks a column the storage worker has not snapshotted since its
	// last change. It is what keeps one record in the persist queue per
	// column rather than one per block written and it is what makes a column
	// ineligible for eviction.
	dirty bool
	// last_used orders columns for eviction against World.column_seq.
	last_used i64
}

// column_key identifies a column by its chunk coordinates. column_key_of takes
// the block coordinates of anything inside it instead. Both halves are packed
// through u64 so a negative coordinate keeps its bit pattern rather than
// riding on what a signed shift does with the sign bit.
fn column_key(cx int, cz int) i64 {
	return i64((u64(u32(cx)) << 32) | u64(u32(cz)))
}

fn column_key_of(x int, z int) i64 {
	return column_key(x >> 4, z >> 4)
}

fn column_coords(key i64) (int, int) {
	return int(i32(u32(u64(key) >> 32))), int(i32(u32(key)))
}

// local_key packs a position into the 16x16xheight space of the column that
// holds it: y whole in the high half, because a column spans every height
// there is, and the two four bit horizontal offsets in the low half.
fn local_key(x int, y int, z int) i64 {
	xz := (u8(x & 15) << 4) | u8(z & 15)
	return i64((u64(u32(y)) << 32) | u64(xz))
}

// local_coords is local_key read back, given the column the position came from.
fn local_coords(cx int, cz int, local i64) (int, int, int) {
	y := int(i32(u32(u64(local) >> 32)))
	xz := int(u32(local) & 0xff)
	return cx * 16 + (xz >> 4), y, cz * 16 + (xz & 15)
}

const column_record_version = u8(1)

// encode_column packs a column into its stored form: a version byte, then the
// block overrides, then the block entities. Both sections carry their own
// count, so a version that appends a third leaves the first two readable.
fn encode_column(c &Column) []u8 {
	mut b := []u8{cap: 1 + 8 + c.blocks.len * 12}
	b << column_record_version
	put_i32(mut b, c.blocks.len)
	for local, id in c.blocks {
		put_i64(mut b, local)
		put_i32(mut b, id)
	}
	put_i32(mut b, c.block_entities.len)
	for local, data in c.block_entities {
		encoded := encode_block_entity(data)
		put_i64(mut b, local)
		put_i32(mut b, encoded.len)
		b << encoded
	}
	return b
}

// decode_column returns none for a record this build cannot read rather than a
// partly filled column. A truncated or future record leaves what is on disk
// alone instead of being silently rewritten from a bad read.
fn decode_column(data []u8) ?&Column {
	if data.len < 5 || data[0] != column_record_version {
		return none
	}
	mut c := &Column{}
	mut at := 1
	block_count := read_i32(data, at)
	at += 4
	if block_count < 0 || at + block_count * 12 > data.len {
		return none
	}
	for _ in 0 .. block_count {
		c.blocks[read_i64(data, at)] = read_i32(data, at + 8)
		at += 12
	}
	if at + 4 > data.len {
		return none
	}
	entity_count := read_i32(data, at)
	at += 4
	for _ in 0 .. entity_count {
		if at + 12 > data.len {
			return none
		}
		local := read_i64(data, at)
		len := read_i32(data, at + 8)
		at += 12
		if len < 0 || at + len > data.len {
			return none
		}
		c.block_entities[local] = decode_block_entity(data[at..at + len]) or { return none }
		at += len
	}
	return c
}
