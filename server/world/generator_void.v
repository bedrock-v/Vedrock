module world

pub const void_spawn_y = 64

pub struct VoidGenerator {
	dim Dimension = overworld
}

pub fn (g VoidGenerator) spawn_y() int {
	return void_spawn_y
}

pub fn (g VoidGenerator) uses_blocks() bool {
	return false
}

pub fn (g VoidGenerator) generate(chunk_x int, chunk_z int) Chunk {
	return new_chunk_dim(g.dim)
}

pub fn (g VoidGenerator) block_at(x int, y int, z int) int {
	return air.network_id
}

pub fn (g VoidGenerator) biome_at(x int, z int) int {
	return default_biome_for(g.dim)
}

pub fn generate_void() Chunk {
	return VoidGenerator{}.generate(0, 0)
}
