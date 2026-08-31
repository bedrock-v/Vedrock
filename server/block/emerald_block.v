module block

import server.world

// EmeraldBlock is the class for 'minecraft:emerald_block'.
pub struct EmeraldBlock {
	SimpleBlock
}

pub fn new_emerald_block() EmeraldBlock {
	return EmeraldBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:emerald_block'
			block_runtime:  world.emerald_block.network_id
			break_hardness: 5.0
		}
	}
}

// new_emerald_block_item is the item form of 'minecraft:emerald_block'.
pub fn new_emerald_block_item() BlockItem {
	return BlockItem{
		id:            'minecraft:emerald_block'
		block_runtime: world.emerald_block.network_id
	}
}
