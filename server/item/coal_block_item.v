module item

import server.world

// CoalBlockItem is the block-item for 'minecraft:coal_block'.
pub struct CoalBlockItem {
	BlockItem
}

pub fn new_coal_block_item() CoalBlockItem {
	return CoalBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:coal_block'
			block_runtime: world.coal_block.network_id
		}
	}
}
