module block

import server.world

// GrassBlock is the class for 'minecraft:grass_block'.
pub struct GrassBlock {
	SimpleBlock
}

pub fn new_grass_block() GrassBlock {
	return GrassBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:grass_block'
			block_runtime:  world.grass_block.network_id
			break_hardness: 0.6
		}
	}
}
