module block

import server.world

// LapisBlock is the class for 'minecraft:lapis_block'.
pub struct LapisBlock {
	SimpleBlock
}

pub fn new_lapis_block() LapisBlock {
	return LapisBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:lapis_block'
			block_runtime:  world.lapis_block.network_id
			break_hardness: 3.0
		}
	}
}
