module block

import server.world

// IronOreBlock is the class for 'minecraft:iron_ore'.
pub struct IronOreBlock {
	SimpleBlock
}

pub fn new_iron_ore() IronOreBlock {
	return IronOreBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:iron_ore'
			block_runtime:  world.iron_ore.network_id
			break_hardness: 3.0
		}
	}
}
