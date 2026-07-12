module item

import server.world

// ClayItem is the block-item for 'minecraft:clay'.
pub struct ClayItem {
	BlockItem
}

pub fn new_clay_item() ClayItem {
	return ClayItem{
		BlockItem: BlockItem{
			id:            'minecraft:clay'
			block_runtime: world.clay.network_id
		}
	}
}
