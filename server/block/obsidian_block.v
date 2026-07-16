module block

import server.world

// ObsidianBlock is the class for 'minecraft:obsidian'.
pub struct ObsidianBlock {
	SimpleBlock
}

pub fn new_obsidian() ObsidianBlock {
	return ObsidianBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:obsidian'
			block_runtime:  world.obsidian.network_id
			break_hardness: 50.0
		}
	}
}
