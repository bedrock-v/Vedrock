module block

import server.world

// CoalBlock is the class for 'minecraft:coal_block'.
pub struct CoalBlock {
	SimpleBlock
}

pub fn new_coal_block() CoalBlock {
	return CoalBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:coal_block'
			block_runtime:  world.coal_block.network_id
			break_hardness: 5.0
		}
	}
}

// new_coal_block_item is the item form of 'minecraft:coal_block'.
pub fn new_coal_block_item() BlockItem {
	return BlockItem{
		id:            'minecraft:coal_block'
		block_runtime: world.coal_block.network_id
	}
}
