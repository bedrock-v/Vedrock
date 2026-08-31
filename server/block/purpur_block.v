module block

import server.world

// PurpurBlock is the class for 'minecraft:purpur_block'.
pub struct PurpurBlock {
	SimpleBlock
}

pub fn new_purpur_block() PurpurBlock {
	return PurpurBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:purpur_block'
			block_runtime:  world.purpur_block.network_id
			break_hardness: 1.5
		}
	}
}

// new_purpur_block_item is the item form of 'minecraft:purpur_block'.
pub fn new_purpur_block_item() BlockItem {
	return BlockItem{
		id:            'minecraft:purpur_block'
		block_runtime: world.purpur_block.network_id
	}
}
