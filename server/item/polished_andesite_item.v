module item

import server.world

// PolishedAndesiteItem is the block-item for 'minecraft:polished_andesite'.
pub struct PolishedAndesiteItem {
	BlockItem
}

pub fn new_polished_andesite_item() PolishedAndesiteItem {
	return PolishedAndesiteItem{
		BlockItem: BlockItem{
			id:            'minecraft:polished_andesite'
			block_runtime: world.polished_andesite.network_id
		}
	}
}
