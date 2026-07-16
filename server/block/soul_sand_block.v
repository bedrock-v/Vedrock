module block

import server.world

// SoulSandBlock is the class for 'minecraft:soul_sand'.
pub struct SoulSandBlock {
	SimpleBlock
}

pub fn new_soul_sand() SoulSandBlock {
	return SoulSandBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:soul_sand'
			block_runtime:  world.soul_sand.network_id
			break_hardness: 0.5
		}
	}
}
