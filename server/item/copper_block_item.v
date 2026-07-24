module item

import server.world

// CopperBlockItem is the block-item for 'minecraft:copper_block'.
pub struct CopperBlockItem {
	BlockItem
}

pub fn new_copper_block_item() CopperBlockItem {
	return CopperBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:copper_block'
			block_runtime: world.copper_block.network_id
		}
	}
}
