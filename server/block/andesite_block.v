module block

import server.world

// AndesiteBlock is the class for 'minecraft:andesite'.
pub struct AndesiteBlock {
	SimpleBlock
}

pub fn new_andesite() AndesiteBlock {
	return AndesiteBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:andesite'
			block_runtime:  world.andesite.network_id
			break_hardness: 1.5
		}
	}
}

// new_andesite_item is the item form of 'minecraft:andesite'.
pub fn new_andesite_item() BlockItem {
	return BlockItem{
		id:            'minecraft:andesite'
		block_runtime: world.andesite.network_id
	}
}
