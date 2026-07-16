module item

import server.world

// DiamondBlockItem is the block-item for 'minecraft:diamond_block'.
pub struct DiamondBlockItem {
	BlockItem
}

pub fn new_diamond_block_item() DiamondBlockItem {
	return DiamondBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:diamond_block'
			block_runtime: world.diamond_block.network_id
		}
	}
}
