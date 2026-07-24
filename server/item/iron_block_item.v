module item

import server.world

// IronBlockItem is the block-item for 'minecraft:iron_block'.
pub struct IronBlockItem {
	BlockItem
}

pub fn new_iron_block_item() IronBlockItem {
	return IronBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:iron_block'
			block_runtime: world.iron_block.network_id
		}
	}
}
