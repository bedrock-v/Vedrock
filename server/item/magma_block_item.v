module item

import server.world

// MagmaBlockItem is the block-item for 'minecraft:magma'.
pub struct MagmaBlockItem {
	BlockItem
}

pub fn new_magma_block_item() MagmaBlockItem {
	return MagmaBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:magma'
			block_runtime: world.magma_block.network_id
		}
	}
}
