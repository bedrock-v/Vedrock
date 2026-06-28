module world

pub const flat_spawn_y = -60
pub const void_spawn_y = 64
pub const normal_base_y = -60
pub const normal_height_variation = 7

pub interface Generator {
	spawn_y() int
	uses_blocks() bool
	generate(chunk_x int, chunk_z int) Chunk
}

pub struct VoidGenerator {}

pub fn (g VoidGenerator) spawn_y() int {
	return void_spawn_y
}

pub fn (g VoidGenerator) uses_blocks() bool {
	return false
}

pub fn (g VoidGenerator) generate(chunk_x int, chunk_z int) Chunk {
	return new_chunk()
}

pub struct FlatGenerator {}

pub fn (g FlatGenerator) spawn_y() int {
	return flat_spawn_y
}

pub fn (g FlatGenerator) uses_blocks() bool {
	return true
}

pub fn (g FlatGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk()
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			c.set_block(x, -64, z, bedrock)
			c.set_block(x, -63, z, dirt)
			c.set_block(x, -62, z, dirt)
			c.set_block(x, -61, z, grass_block)
		}
	}
	return c
}

pub struct NormalGenerator {}

pub fn (g NormalGenerator) spawn_y() int {
	return surface_height(0, 0) + 1
}

pub fn (g NormalGenerator) uses_blocks() bool {
	return true
}

pub fn (g NormalGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk()
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			height := surface_height(chunk_x * 16 + x, chunk_z * 16 + z)
			c.set_block(x, -64, z, bedrock)
			for y in -63 .. height - 2 {
				c.set_block(x, y, z, stone)
			}
			for y in height - 2 .. height {
				c.set_block(x, y, z, dirt)
			}
			c.set_block(x, height, z, grass_block)
		}
	}
	return c
}

fn surface_height(world_x int, world_z int) int {
	mut b := []u8{}
	put_u32_le(mut b, u32(world_x))
	put_u32_le(mut b, u32(world_z))
	return normal_base_y + int(fnv1a_32(b) % u32(normal_height_variation))
}

pub fn new_generator(name string) Generator {
	mut g := Generator(FlatGenerator{})
	match name.to_lower() {
		'void' { g = VoidGenerator{} }
		'normal' { g = NormalGenerator{} }
		else {}
	}
	return g
}

pub fn generate_flat() Chunk {
	return FlatGenerator{}.generate(0, 0)
}

pub fn generate_void() Chunk {
	return VoidGenerator{}.generate(0, 0)
}
