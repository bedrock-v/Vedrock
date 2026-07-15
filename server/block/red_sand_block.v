module block

import server.world

// RedSandBlock is the class for 'minecraft:red_sand'.
pub struct RedSandBlock {
	SimpleBlock
}

pub fn new_red_sand() RedSandBlock {
	return RedSandBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:red_sand'
			block_runtime:  world.red_sand.network_id
			break_hardness: 0.5
		}
	}
}
