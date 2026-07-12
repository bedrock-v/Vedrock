module block

import server.world

// DiamondBlock is the class for 'minecraft:diamond_block'.
pub struct DiamondBlock {
	SimpleBlock
}

pub fn new_diamond_block() DiamondBlock {
	return DiamondBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:diamond_block'
			block_runtime:  world.diamond_block.network_id
			break_hardness: 5.0
		}
	}
}
