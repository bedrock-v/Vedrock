module block

import server.world

// SandBlock is the class for 'minecraft:sand'.
pub struct SandBlock {
	SimpleBlock
}

pub fn new_sand() SandBlock {
	return SandBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:sand'
			block_runtime:  world.sand.network_id
			break_hardness: 0.5
		}
	}
}

// new_sand_item is the item form of 'minecraft:sand'.
pub fn new_sand_item() BlockItem {
	return BlockItem{
		id:            'minecraft:sand'
		block_runtime: world.sand.network_id
	}
}
