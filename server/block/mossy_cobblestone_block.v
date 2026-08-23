module block

import server.world

// MossyCobblestoneBlock is the class for 'minecraft:mossy_cobblestone'.
pub struct MossyCobblestoneBlock {
	SimpleBlock
}

pub fn new_mossy_cobblestone() MossyCobblestoneBlock {
	return MossyCobblestoneBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:mossy_cobblestone'
			block_runtime:  world.mossy_cobblestone.network_id
			break_hardness: 2.0
		}
	}
}

// new_mossy_cobblestone_item is the item form of 'minecraft:mossy_cobblestone'.
pub fn new_mossy_cobblestone_item() BlockItem {
	return BlockItem{
		id:            'minecraft:mossy_cobblestone'
		block_runtime: world.mossy_cobblestone.network_id
	}
}
