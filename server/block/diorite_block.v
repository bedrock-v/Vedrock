module block

import server.world

// DioriteBlock is the class for 'minecraft:diorite'.
pub struct DioriteBlock {
	SimpleBlock
}

pub fn new_diorite() DioriteBlock {
	return DioriteBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:diorite'
			block_runtime:  world.diorite.network_id
			break_hardness: 1.5
		}
	}
}
