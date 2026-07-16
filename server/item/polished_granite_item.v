module item

import server.world

// PolishedGraniteItem is the block-item for 'minecraft:polished_granite'.
pub struct PolishedGraniteItem {
	BlockItem
}

pub fn new_polished_granite_item() PolishedGraniteItem {
	return PolishedGraniteItem{
		BlockItem: BlockItem{
			id:            'minecraft:polished_granite'
			block_runtime: world.polished_granite.network_id
		}
	}
}
