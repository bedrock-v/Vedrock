module block

import server.world

// PolishedGraniteBlock is the class for 'minecraft:polished_granite'.
pub struct PolishedGraniteBlock {
	SimpleBlock
}

pub fn new_polished_granite() PolishedGraniteBlock {
	return PolishedGraniteBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:polished_granite'
			block_runtime:  world.polished_granite.network_id
			break_hardness: 1.5
		}
	}
}
