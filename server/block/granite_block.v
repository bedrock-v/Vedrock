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
