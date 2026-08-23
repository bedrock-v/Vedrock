module block

import server.world

// EndStoneBlock is the class for 'minecraft:end_stone'.
pub struct EndStoneBlock {
	SimpleBlock
}

pub fn new_end_stone() EndStoneBlock {
	return EndStoneBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:end_stone'
			block_runtime:  world.end_stone.network_id
			break_hardness: 3.0
		}
	}
}

// new_end_stone_item is the item form of 'minecraft:end_stone'.
pub fn new_end_stone_item() BlockItem {
	return BlockItem{
		id:            'minecraft:end_stone'
		block_runtime: world.end_stone.network_id
	}
}
