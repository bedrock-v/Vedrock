module item

import server.world

// RedstoneBlockItem is the block-item for 'minecraft:redstone_block'.
pub struct RedstoneBlockItem {
	BlockItem
}

pub fn new_redstone_block_item() RedstoneBlockItem {
	return RedstoneBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:redstone_block'
			block_runtime: world.redstone_block.network_id
		}
	}
}
