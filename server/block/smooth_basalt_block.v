module block

import server.world

// SmoothBasaltBlock is the class for 'minecraft:smooth_basalt'.
pub struct SmoothBasaltBlock {
	SimpleBlock
}

pub fn new_smooth_basalt() SmoothBasaltBlock {
	return SmoothBasaltBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:smooth_basalt'
			block_runtime:  world.smooth_basalt.network_id
			break_hardness: 1.25
		}
	}
}
