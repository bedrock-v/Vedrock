module item

import server.world

// DripstoneBlockItem is the block-item for 'minecraft:dripstone_block'.
pub struct DripstoneBlockItem {
	BlockItem
}

pub fn new_dripstone_block_item() DripstoneBlockItem {
	return DripstoneBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:dripstone_block'
			block_runtime: world.dripstone_block.network_id
		}
	}
}
