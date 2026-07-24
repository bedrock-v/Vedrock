module item

import server.world

// StoneItem is the class for 'minecraft:stone'.
pub struct StoneItem {
	BlockItem
}

pub fn new_stone_item() StoneItem {
	return StoneItem{
		BlockItem: BlockItem{
			id:            'minecraft:stone'
			block_runtime: world.stone.network_id
		}
	}
}
