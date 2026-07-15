module block

import server.world

// LapisOreBlock is the class for 'minecraft:lapis_ore'.
pub struct LapisOreBlock {
	SimpleBlock
}

pub fn new_lapis_ore() LapisOreBlock {
	return LapisOreBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:lapis_ore'
			block_runtime:  world.lapis_ore.network_id
			break_hardness: 3.0
		}
	}
}
