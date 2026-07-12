module item

import server.world

// TuffItem is the block-item for 'minecraft:tuff'.
pub struct TuffItem {
	BlockItem
}

pub fn new_tuff_item() TuffItem {
	return TuffItem{
		BlockItem: BlockItem{
			id:            'minecraft:tuff'
			block_runtime: world.tuff.network_id
		}
	}
}
