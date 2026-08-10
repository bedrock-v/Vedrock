module world

pub const flat_spawn_y = -60

// fill_flat_layers fills every column of c with blocks bottom up starting at
// base_y.
fn fill_flat_layers(mut c Chunk, base_y int, layers []Block) {
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			for i, b in layers {
				c.set_block(x, base_y + i, z, b)
			}
		}
	}
}

// flat_layer_at is fill_flat_layers' block_at counterpart.
fn flat_layer_at(y int, base_y int, layers []Block) int {
	offset := y - base_y
	if offset < 0 || offset >= layers.len {
		return air.network_id
	}
	return layers[offset].network_id
}

pub struct FlatGenerator {
	dim Dimension = overworld
}

fn (g FlatGenerator) layers() []Block {
	return [bedrock, dirt, dirt, grass_block]
}

pub fn (g FlatGenerator) spawn_y() int {
	return safe_spawn_y(g, g.dim, 0, 0, g.dim.min_y + g.layers().len)
}

pub fn (g FlatGenerator) uses_blocks() bool {
	return true
}

pub fn (g FlatGenerator) generate(chunk_x int, chunk_z int) Chunk {
	mut c := new_chunk_dim(g.dim)
	fill_flat_layers(mut c, g.dim.min_y, g.layers())
	biome := default_biome_for(g.dim)
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			c.set_biome(x, z, biome)
		}
	}
	return c
}

pub fn (g FlatGenerator) block_at(x int, y int, z int) int {
	return flat_layer_at(y, g.dim.min_y, g.layers())
}

pub fn (g FlatGenerator) biome_at(x int, z int) int {
	return default_biome_for(g.dim)
}

pub fn generate_flat() Chunk {
	return FlatGenerator{}.generate(0, 0)
}
