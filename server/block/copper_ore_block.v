module block

import server.world

// CopperOreBlock is the class for 'minecraft:copper_ore'.
pub struct CopperOreBlock {
	SimpleBlock
}

pub fn new_copper_ore() CopperOreBlock {
	return CopperOreBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:copper_ore'
			block_runtime:  world.copper_ore.network_id
			break_hardness: 3.0
		}
	}
}
