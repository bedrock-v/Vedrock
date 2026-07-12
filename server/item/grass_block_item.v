module item

import server.world

// GrassBlockItem is the class for 'minecraft:grass_block'.
pub struct GrassBlockItem {
	BlockItem
}

pub fn new_grass_block_item() GrassBlockItem {
	return GrassBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:grass_block'
			block_runtime: world.grass_block.network_id
		}
	}
}
