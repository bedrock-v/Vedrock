module block

import server.world

// IronBlock is the class for 'minecraft:iron_block'.
pub struct IronBlock {
	SimpleBlock
}

pub fn new_iron_block() IronBlock {
	return IronBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:iron_block'
			block_runtime:  world.iron_block.network_id
			break_hardness: 5.0
		}
	}
}
