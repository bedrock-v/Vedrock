module block

import server.world

// GravelBlock is the class for 'minecraft:gravel'.
pub struct GravelBlock {
	SimpleBlock
}

pub fn new_gravel() GravelBlock {
	return GravelBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:gravel'
			block_runtime:  world.gravel.network_id
			break_hardness: 0.6
		}
	}
}
