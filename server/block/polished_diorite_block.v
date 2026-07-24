module block

import server.world

// PolishedDioriteBlock is the class for 'minecraft:polished_diorite'.
pub struct PolishedDioriteBlock {
	SimpleBlock
}

pub fn new_polished_diorite() PolishedDioriteBlock {
	return PolishedDioriteBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:polished_diorite'
			block_runtime:  world.polished_diorite.network_id
			break_hardness: 1.5
		}
	}
}
