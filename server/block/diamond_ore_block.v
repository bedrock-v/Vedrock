module block

import server.world

// DiamondOreBlock is the class for 'minecraft:diamond_ore'.
pub struct DiamondOreBlock {
	SimpleBlock
}

pub fn new_diamond_ore() DiamondOreBlock {
	return DiamondOreBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:diamond_ore'
			block_runtime:  world.diamond_ore.network_id
			break_hardness: 3.0
		}
	}
}
