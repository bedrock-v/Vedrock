module block

import server.world

// SnowBlock is the class for 'minecraft:snow'.
pub struct SnowBlock {
	SimpleBlock
}

pub fn new_snow() SnowBlock {
	return SnowBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:snow'
			block_runtime:  world.snow.network_id
			break_hardness: 0.2
		}
	}
}
