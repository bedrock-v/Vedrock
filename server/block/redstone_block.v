module block

import server.world

// RedstoneBlock is the class for 'minecraft:redstone_block'.
pub struct RedstoneBlock {
	SimpleBlock
}

pub fn new_redstone_block() RedstoneBlock {
	return RedstoneBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:redstone_block'
			block_runtime:  world.redstone_block.network_id
			break_hardness: 5.0
		}
	}
}
