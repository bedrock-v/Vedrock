module block

import server.world

// StoneBlock is the class for 'minecraft:stone'.
pub struct StoneBlock {
	SimpleBlock
}

pub fn new_stone_block() StoneBlock {
	return StoneBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:stone'
			block_runtime:  world.stone.network_id
			break_hardness: 1.5
		}
	}
}
