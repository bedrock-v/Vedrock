module block

import server.world

// AndesiteBlock is the class for 'minecraft:andesite'.
pub struct AndesiteBlock {
	SimpleBlock
}

pub fn new_andesite() AndesiteBlock {
	return AndesiteBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:andesite'
			block_runtime:  world.andesite.network_id
			break_hardness: 1.5
		}
	}
}
