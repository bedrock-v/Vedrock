module item

import server.world

// EmeraldBlockItem is the block-item for 'minecraft:emerald_block'.
pub struct EmeraldBlockItem {
	BlockItem
}

pub fn new_emerald_block_item() EmeraldBlockItem {
	return EmeraldBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:emerald_block'
			block_runtime: world.emerald_block.network_id
		}
	}
}
