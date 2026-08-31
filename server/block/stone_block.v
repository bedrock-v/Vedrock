module block

import server.world

// StoneBlock is the class for 'minecraft:stone'.
pub struct StoneBlock {
	SimpleBlock
}

pub fn new_stone_block() StoneBlock {
	return StoneBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:stone'
			block_runtime:  world.stone.network_id
			break_hardness: 1.5
		}
	}
}

// new_stone_item is the item form of 'minecraft:stone'.
pub fn new_stone_item() BlockItem {
	return BlockItem{
		id:            'minecraft:stone'
		block_runtime: world.stone.network_id
	}
}
