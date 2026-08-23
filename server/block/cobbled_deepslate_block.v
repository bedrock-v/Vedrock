module block

import server.world

// CobbledDeepslateBlock is the class for 'minecraft:cobbled_deepslate'.
pub struct CobbledDeepslateBlock {
	SimpleBlock
}

pub fn new_cobbled_deepslate() CobbledDeepslateBlock {
	return CobbledDeepslateBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:cobbled_deepslate'
			block_runtime:  world.cobbled_deepslate.network_id
			break_hardness: 3.5
		}
	}
}

// new_cobbled_deepslate_item is the item form of 'minecraft:cobbled_deepslate'.
pub fn new_cobbled_deepslate_item() BlockItem {
	return BlockItem{
		id:            'minecraft:cobbled_deepslate'
		block_runtime: world.cobbled_deepslate.network_id
	}
}
