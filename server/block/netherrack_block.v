module block

import server.world

// NetherrackBlock is the class for 'minecraft:netherrack'.
pub struct NetherrackBlock {
	SimpleBlock
}

pub fn new_netherrack() NetherrackBlock {
	return NetherrackBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:netherrack'
			block_runtime:  world.netherrack.network_id
			break_hardness: 0.4
		}
	}
}

// new_netherrack_item is the item form of 'minecraft:netherrack'.
pub fn new_netherrack_item() BlockItem {
	return BlockItem{
		id:            'minecraft:netherrack'
		block_runtime: world.netherrack.network_id
	}
}
