module block

import server.world

// CopperBlock is the class for 'minecraft:copper_block'.
pub struct CopperBlock {
	SimpleBlock
}

pub fn new_copper_block() CopperBlock {
	return CopperBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:copper_block'
			block_runtime:  world.copper_block.network_id
			break_hardness: 3.0
		}
	}
}

// new_copper_block_item is the item form of 'minecraft:copper_block'.
pub fn new_copper_block_item() BlockItem {
	return BlockItem{
		id:            'minecraft:copper_block'
		block_runtime: world.copper_block.network_id
	}
}
