module block

import server.world

// RedstoneOreBlock is the class for 'minecraft:redstone_ore'.
pub struct RedstoneOreBlock {
	SimpleBlock
}

pub fn new_redstone_ore() RedstoneOreBlock {
	return RedstoneOreBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:redstone_ore'
			block_runtime:  world.redstone_ore.network_id
			break_hardness: 3.0
		}
	}
}
