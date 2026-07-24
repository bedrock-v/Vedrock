module block

import server.world

// DripstoneBlock is the class for 'minecraft:dripstone_block'.
pub struct DripstoneBlock {
	SimpleBlock
}

pub fn new_dripstone_block() DripstoneBlock {
	return DripstoneBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:dripstone_block'
			block_runtime:  world.dripstone_block.network_id
			break_hardness: 1.5
		}
	}
}
