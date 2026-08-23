module block

import server.world

// ClayBlock is the class for 'minecraft:clay'.
pub struct ClayBlock {
	SimpleBlock
}

pub fn new_clay() ClayBlock {
	return ClayBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:clay'
			block_runtime:  world.clay.network_id
			break_hardness: 0.6
		}
	}
}

// new_clay_item is the item form of 'minecraft:clay'.
pub fn new_clay_item() BlockItem {
	return BlockItem{
		id:            'minecraft:clay'
		block_runtime: world.clay.network_id
	}
}
