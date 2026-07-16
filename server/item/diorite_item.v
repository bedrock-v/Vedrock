module item

import server.world

// DioriteItem is the block-item for 'minecraft:diorite'.
pub struct DioriteItem {
	BlockItem
}

pub fn new_diorite_item() DioriteItem {
	return DioriteItem{
		BlockItem: BlockItem{
			id:            'minecraft:diorite'
			block_runtime: world.diorite.network_id
		}
	}
}
