module block

import server.world

// SandBlock is the class for 'minecraft:sand'.
pub struct SandBlock {
	SimpleBlock
}

pub fn new_sand() SandBlock {
	return SandBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:sand'
			block_runtime:  world.sand.network_id
			break_hardness: 0.5
		}
	}
}
