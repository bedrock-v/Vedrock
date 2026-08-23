module block

import server.world

// TuffBlock is the class for 'minecraft:tuff'.
pub struct TuffBlock {
	SimpleBlock
}

pub fn new_tuff() TuffBlock {
	return TuffBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:tuff'
			block_runtime:  world.tuff.network_id
			break_hardness: 1.5
		}
	}
}

// new_tuff_item is the item form of 'minecraft:tuff'.
pub fn new_tuff_item() BlockItem {
	return BlockItem{
		id:            'minecraft:tuff'
		block_runtime: world.tuff.network_id
	}
}
