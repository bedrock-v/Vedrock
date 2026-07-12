module item

import server.world

// DirtItem is the class for 'minecraft:dirt'.
pub struct DirtItem {
	BlockItem
}

pub fn new_dirt_item() DirtItem {
	return DirtItem{
		BlockItem: BlockItem{
			id:            'minecraft:dirt'
			block_runtime: world.dirt.network_id
		}
	}
}
