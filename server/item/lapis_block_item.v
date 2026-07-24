module item

import server.world

// LapisBlockItem is the block-item for 'minecraft:lapis_block'.
pub struct LapisBlockItem {
	BlockItem
}

pub fn new_lapis_block_item() LapisBlockItem {
	return LapisBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:lapis_block'
			block_runtime: world.lapis_block.network_id
		}
	}
}
