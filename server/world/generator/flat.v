module generator

import server.world
import server.world.block
import server.world.chunk

// Flat lays the same layers of blocks under every chunk, from the bottom of the
// world up, all in one biome.
@[noinit]
pub struct Flat {
	biome  u32
	layers []u32
}

// new_flat is a flat world of these blocks in a biome, the bottom layer first.
pub fn new_flat(biome u32, layers []block.State) !Flat {
	mut ids := []u32{cap: layers.len}
	for s in layers {
		ids << block.vanilla().id(s) or { return error('${s.name} is not a vanilla block state') }
	}
	if ids.len > chunk.max_y - chunk.min_y + 1 {
		return error('${ids.len} layers are taller than the world')
	}
	return Flat{
		biome:  biome
		layers: ids
	}
}

pub fn (f Flat) generate_chunk(pos chunk.Pos, mut c chunk.Chunk) {
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			for i, id in f.layers {
				c.set_block(x, chunk.min_y + i, z, 0, id)
			}
			for y in chunk.min_y .. chunk.max_y + 1 {
				c.set_biome(x, y, z, f.biome)
			}
		}
	}
}

// default_spawn is standing on the top layer.
pub fn (f Flat) default_spawn() world.BlockPos {
	return world.BlockPos{0, chunk.min_y + f.layers.len, 0}
}
