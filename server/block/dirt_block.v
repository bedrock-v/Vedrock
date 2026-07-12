module block

import server.world

// DirtBlock is the class for 'minecraft:dirt'.
pub struct DirtBlock {
	SimpleBlock
}

pub fn new_dirt_block() DirtBlock {
	return DirtBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:dirt'
			block_runtime:  world.dirt.network_id
			break_hardness: 0.5
		}
	}
}
