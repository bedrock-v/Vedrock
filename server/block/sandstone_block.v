module block

import server.world

// SandstoneBlock is the class for 'minecraft:sandstone'.
pub struct SandstoneBlock {
	SimpleBlock
}

pub fn new_sandstone() SandstoneBlock {
	return SandstoneBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:sandstone'
			block_runtime:  world.sandstone.network_id
			break_hardness: 0.8
		}
	}
}

// new_sandstone_item is the item form of 'minecraft:sandstone'.
pub fn new_sandstone_item() BlockItem {
	return BlockItem{
		id:            'minecraft:sandstone'
		block_runtime: world.sandstone.network_id
	}
}
