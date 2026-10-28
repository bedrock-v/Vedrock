module world

import server.world.chunk

// BlockPos is a block's position in a world.
pub struct BlockPos {
pub:
	x int
	y int
	z int
}

// Generator fills the chunks a world has never had. A world has one and asks it
// once for every chunk it needs.
//
// It runs on the world's thread. A generator that takes long holds up the
// whole world.
pub interface Generator {
	// generate_chunk fills a new chunk at a position.
	generate_chunk(pos chunk.Pos, mut c chunk.Chunk)
	// default_spawn is where a world using this generator puts new players.
	default_spawn() BlockPos
}

// NopGenerator places nothing and leaves the world empty.
pub struct NopGenerator {}

pub fn (g NopGenerator) generate_chunk(pos chunk.Pos, mut c chunk.Chunk) {}

pub fn (g NopGenerator) default_spawn() BlockPos {
	return BlockPos{0, 100, 0}
}
