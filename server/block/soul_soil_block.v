module block

import server.world

// SoulSoilBlock is the class for 'minecraft:soul_soil'.
pub struct SoulSoilBlock {
	SimpleBlock
}

pub fn new_soul_soil() SoulSoilBlock {
	return SoulSoilBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:soul_soil'
			block_runtime:  world.soul_soil.network_id
			break_hardness: 0.5
		}
	}
}
