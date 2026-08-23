module block

import server.world

// CobblestoneBlock is the class for 'minecraft:cobblestone'.
pub struct CobblestoneBlock {
	SimpleBlock
}

pub fn new_cobblestone() CobblestoneBlock {
	return CobblestoneBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:cobblestone'
			block_runtime:  world.cobblestone.network_id
			break_hardness: 2.0
		}
	}
}

// new_cobblestone_item is the item form of 'minecraft:cobblestone'.
pub fn new_cobblestone_item() BlockItem {
	return BlockItem{
		id:            'minecraft:cobblestone'
		block_runtime: world.cobblestone.network_id
	}
}
