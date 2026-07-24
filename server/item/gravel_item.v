module item

import server.world

// GravelItem is the block-item for 'minecraft:gravel'.
pub struct GravelItem {
	BlockItem
}

pub fn new_gravel_item() GravelItem {
	return GravelItem{
		BlockItem: BlockItem{
			id:            'minecraft:gravel'
			block_runtime: world.gravel.network_id
		}
	}
}
