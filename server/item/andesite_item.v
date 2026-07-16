module item

import server.world

// AndesiteItem is the block-item for 'minecraft:andesite'.
pub struct AndesiteItem {
	BlockItem
}

pub fn new_andesite_item() AndesiteItem {
	return AndesiteItem{
		BlockItem: BlockItem{
			id:            'minecraft:andesite'
			block_runtime: world.andesite.network_id
		}
	}
}
