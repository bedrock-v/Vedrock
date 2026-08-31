module block

import server.world

// PolishedAndesiteBlock is the class for 'minecraft:polished_andesite'.
pub struct PolishedAndesiteBlock {
	SimpleBlock
}

pub fn new_polished_andesite() PolishedAndesiteBlock {
	return PolishedAndesiteBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:polished_andesite'
			block_runtime:  world.polished_andesite.network_id
			break_hardness: 1.5
		}
	}
}

// new_polished_andesite_item is the item form of 'minecraft:polished_andesite'.
pub fn new_polished_andesite_item() BlockItem {
	return BlockItem{
		id:            'minecraft:polished_andesite'
		block_runtime: world.polished_andesite.network_id
	}
}
