module block

import server.world

// IceBlock is the class for 'minecraft:ice'.
pub struct IceBlock {
	SimpleBlock
}

pub fn new_ice() IceBlock {
	return IceBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:ice'
			block_runtime:  world.ice.network_id
			break_hardness: 0.5
		}
	}
}
