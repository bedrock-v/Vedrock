module block

import server.world

// MagmaBlock is the class for 'minecraft:magma'.
pub struct MagmaBlock {
	SimpleBlock
}

pub fn new_magma_block() MagmaBlock {
	return MagmaBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:magma'
			block_runtime:  world.magma_block.network_id
			break_hardness: 0.5
		}
	}
}
