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

pub fn build_chunk(flat bool) (u32, []u8) {
	chunk := if flat { generate_flat() } else { generate_void() }
	return u32(chunk.section_count()), chunk.serialize()
}

pub fn uses_block_hashes(flat bool) bool {
	return flat
}
