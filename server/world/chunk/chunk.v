module chunk

import bedrock_v.protocol.serializer
import server.world.block

// min_y and max_y are the lowest and highest block of an overworld chunk.
pub const min_y = -64
pub const max_y = 319

// overworld_sections is how many 16 block tall sections an overworld chunk has.
pub const overworld_sections = (max_y - min_y + 1) / 16

// plains_biome is the biome a new chunk has everywhere.
pub const plains_biome = u32(1)

// sub_chunk_version is the format of the sub chunks encode writes.
const sub_chunk_version = u8(9)

// Pos is a chunk's position in chunks.
pub struct Pos {
pub:
	x int
	z int
}

// Chunk is a 16 by 16 column of the world from the bottom to the top. It holds
// a block ID from its registry for every block and layer, and a biome.
//
// Layer 0 is the block itself. Layer 1 is what shares its space, the water of a
// waterlogged block.
pub struct Chunk {
	blocks &block.Registry
mut:
	sections []SubChunk
	biomes   []Storage
}

// SubChunk is one 16 block tall section of a chunk. It has no layers until a
// block is set on one.
struct SubChunk {
mut:
	layers []Storage
}

// new is an overworld chunk of air in the plains.
pub fn new(blocks &block.Registry) Chunk {
	return Chunk{
		blocks:   blocks
		sections: []SubChunk{len: overworld_sections}
		biomes:   []Storage{len: overworld_sections, init: new_storage(plains_biome)}
	}
}

// block is the block at a position on a layer. x and z are within the chunk
// and y is the world's.
pub fn (c &Chunk) block(x int, y int, z int, layer int) u32 {
	section, i := locate(x, y, z)
	layers := c.sections[section].layers
	if layer >= layers.len {
		return c.blocks.air
	}
	return layers[layer].at(i)
}

// set_block puts a block at a position on a layer.
pub fn (mut c Chunk) set_block(x int, y int, z int, layer int, id u32) {
	if id >= u32(c.blocks.len()) {
		panic('chunk: block ID ${id} is not in the registry')
	}
	section, i := locate(x, y, z)
	mut sub := &c.sections[section]
	for sub.layers.len <= layer {
		sub.layers << new_storage(c.blocks.air)
	}
	sub.layers[layer].set(i, id)
}

// biome is the biome at a position.
pub fn (c &Chunk) biome(x int, y int, z int) u32 {
	section, i := locate(x, y, z)
	return c.biomes[section].at(i)
}

// set_biome sets the biome at a position.
pub fn (mut c Chunk) set_biome(x int, y int, z int, biome u32) {
	section, i := locate(x, y, z)
	c.biomes[section].set(i, biome)
}

// locate is the section a position is in and its index there. A position
// outside the chunk is a bug in whoever asked.
fn locate(x int, y int, z int) (int, int) {
	if x < 0 || x > 15 || z < 0 || z > 15 || y < min_y || y > max_y {
		panic('chunk: ${x} ${y} ${z} is outside the chunk')
	}
	return (y - min_y) >> 4, block_index(x, (y - min_y) & 15, z)
}

// compact makes every storage as small as the blocks and biomes in it allow.
// Call it before encode on a chunk that had blocks set and replaced.
pub fn (mut c Chunk) compact() {
	for mut sub in c.sections {
		for mut layer in sub.layers {
			layer.compact()
		}
	}
	for mut biomes in c.biomes {
		biomes.compact()
	}
}

// encode is the chunk as a LevelChunk packet carries it and how many sub
// chunks that is: the sub chunks up to the highest one holding anything, the
// biomes of every section and the border blocks.
pub fn (c &Chunk) encode() ([]u8, int) {
	mut count := c.sections.len
	for count > 0 && c.empty(c.sections[count - 1]) {
		count--
	}
	mut w := serializer.new_writer()
	for i in 0 .. count {
		sub := c.sections[i]
		w.u8(sub_chunk_version)
		w.u8(u8(sub.layers.len))
		w.u8(u8(i + (min_y >> 4)))
		for layer in sub.layers {
			c.write_storage(mut w, layer, true)
		}
	}
	for i, biomes in c.biomes {
		// 0x7f in the bits says the section has the same biomes as the one below.
		if i > 0 && biomes.same(c.biomes[i - 1]) {
			w.u8(0x7f << 1 | 1)
		} else {
			c.write_storage(mut w, biomes, false)
		}
	}
	// No border blocks.
	w.u8(0)
	return w.bytes(), count
}

// empty reports whether a section holds nothing but air. A section that held a
// block once keeps it in its palette and counts as holding something.
fn (c &Chunk) empty(sub SubChunk) bool {
	for layer in sub.layers {
		if layer.palette != [c.blocks.air] {
			return false
		}
	}
	return true
}

// write_storage writes a storage as the network carries it. The low bit of the
// first byte marks the network form whose palette is varints. Blocks go out
// as their network ID, the hash of their state and biomes as they are.
fn (c &Chunk) write_storage(mut w serializer.Writer, s Storage, blocks bool) {
	w.u8(u8(s.bits << 1 | 1))
	for word in s.words {
		w.le_u32(word)
	}
	if s.bits != 0 {
		w.write_varint32(i32(s.palette.len))
	}
	for v in s.palette {
		w.write_varint32(i32(if blocks { c.blocks.hash(v) } else { v }))
	}
}
