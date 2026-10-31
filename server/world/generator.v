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
// It runs on the world's generation workers, not its thread, so a slow one
// delays only the chunks it is filling. There is one worker unless
// Config.chunk_workers says otherwise. With more, generate_chunk is called
// from several threads at once and has to be safe for that.
//
// A generator that panics takes the whole process down with it.
pub interface Generator {
	// generate_chunk fills a new chunk at a position. The chunk starts as air in
	// the plains and its blocks are IDs from block.vanilla().
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
