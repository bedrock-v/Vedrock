module item

import server.world

// PurpurBlockItem is the block-item for 'minecraft:purpur_block'.
pub struct PurpurBlockItem {
	BlockItem
}

pub fn new_purpur_block_item() PurpurBlockItem {
	return PurpurBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:purpur_block'
			block_runtime: world.purpur_block.network_id
		}
	}
}
