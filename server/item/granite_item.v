module item

import server.world

// GraniteItem is the block-item for 'minecraft:granite'.
pub struct GraniteItem {
	BlockItem
}

pub fn new_granite_item() GraniteItem {
	return GraniteItem{
		BlockItem: BlockItem{
			id:            'minecraft:granite'
			block_runtime: world.granite.network_id
		}
	}
}
