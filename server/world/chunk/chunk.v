module chunk

import bedrock_v.protocol.serializer

// overworld_sections is how many 16 block tall sections an overworld chunk has,
// from y -64 to 319.
pub const overworld_sections = 24

// Pos is a chunk's position in chunks.
pub struct Pos {
pub:
	x int
	z int
}

// Chunk is a 16 by 16 column of the world from the bottom to the top.
pub struct Chunk {
pub:
	sections int = overworld_sections
}

// new is an overworld chunk of air.
pub fn new() Chunk {
	return Chunk{}
}

// encode is the chunk as a LevelChunk packet carries it: the sub chunks, the
// biomes of every section and the border blocks.
//
// A chunk of air has no sub chunks to send. Biomes are a palette per section.
// The first is the single biome 0 and every one after it repeats the one
// below it which is 0x7f in the length bits.
pub fn (c &Chunk) encode() []u8 {
	mut w := serializer.new_writer()
	w.u8(0 << 1 | 1)
	w.write_varint32(0)
	for _ in 1 .. c.sections {
		w.u8(0x7f << 1 | 1)
	}
	// No border blocks.
	w.u8(0)
	return w.bytes()
}
