module world

pub const flat_surface_y = 63

pub fn generate_void() Chunk {
	return new_chunk()
}

pub fn generate_flat() Chunk {
	mut c := new_chunk()
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			for y in dimension_min_y .. flat_surface_y {
				c.set_block(x, y, z, stone)
			}
			c.set_block(x, flat_surface_y, z, grass_block)
		}
	}
	return c
}

pub fn chunk_payload(flat bool) []u8 {
	if flat {
		chunk := generate_flat()
		return chunk.serialize()
	}
	chunk := generate_void()
	return chunk.serialize()
}

pub fn uses_block_hashes(flat bool) bool {
	return flat
}
