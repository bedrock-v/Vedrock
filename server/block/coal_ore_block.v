module block

import server.world

// CoalOreBlock is the class for 'minecraft:coal_ore'.
pub struct CoalOreBlock {
	SimpleBlock
}

pub fn new_coal_ore() CoalOreBlock {
	return CoalOreBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:coal_ore'
			block_runtime:  world.coal_ore.network_id
			break_hardness: 3.0
		}
	}
}
