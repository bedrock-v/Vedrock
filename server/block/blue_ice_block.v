module block

import server.world

// BlueIceBlock is the class for 'minecraft:blue_ice'.
pub struct BlueIceBlock {
	SimpleBlock
}

pub fn new_blue_ice() BlueIceBlock {
	return BlueIceBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:blue_ice'
			block_runtime:  world.blue_ice.network_id
			break_hardness: 2.8
		}
	}
}
