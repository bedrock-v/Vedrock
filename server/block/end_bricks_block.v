module block

import server.world

// EndBricksBlock is the class for 'minecraft:end_bricks'.
pub struct EndBricksBlock {
	SimpleBlock
}

pub fn new_end_bricks() EndBricksBlock {
	return EndBricksBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:end_bricks'
			block_runtime:  world.end_bricks.network_id
			break_hardness: 0.8
		}
	}
}
