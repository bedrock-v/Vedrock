module block

import server.world

// GoldBlock is the class for 'minecraft:gold_block'.
pub struct GoldBlock {
	SimpleBlock
}

pub fn new_gold_block() GoldBlock {
	return GoldBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:gold_block'
			block_runtime:  world.gold_block.network_id
			break_hardness: 3.0
		}
	}
}

// new_gold_block_item is the item form of 'minecraft:gold_block'.
pub fn new_gold_block_item() BlockItem {
	return BlockItem{
		id:            'minecraft:gold_block'
		block_runtime: world.gold_block.network_id
	}
}
