module block

import server.world

// GlowstoneBlock is the class for 'minecraft:glowstone'.
pub struct GlowstoneBlock {
	SimpleBlock
}

pub fn new_glowstone() GlowstoneBlock {
	return GlowstoneBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:glowstone'
			block_runtime:  world.glowstone.network_id
			break_hardness: 0.3
		}
	}
}
