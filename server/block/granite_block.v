module block

import server.world

// GraniteBlock is the class for 'minecraft:granite'.
pub struct GraniteBlock {
	SimpleBlock
}

pub fn new_granite() GraniteBlock {
	return GraniteBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:granite'
			block_runtime:  world.granite.network_id
			break_hardness: 1.5
		}
	}
}

// new_granite_item is the item form of 'minecraft:granite'.
pub fn new_granite_item() BlockItem {
	return BlockItem{
		id:            'minecraft:granite'
		block_runtime: world.granite.network_id
	}
}
