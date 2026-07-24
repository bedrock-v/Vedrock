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
