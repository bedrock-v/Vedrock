module item

import server.world

// PolishedDioriteItem is the block-item for 'minecraft:polished_diorite'.
pub struct PolishedDioriteItem {
	BlockItem
}

pub fn new_polished_diorite_item() PolishedDioriteItem {
	return PolishedDioriteItem{
		BlockItem: BlockItem{
			id:            'minecraft:polished_diorite'
			block_runtime: world.polished_diorite.network_id
		}
	}
}
