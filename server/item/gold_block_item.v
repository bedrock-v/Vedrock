module item

import server.world

// GoldBlockItem is the block-item for 'minecraft:gold_block'.
pub struct GoldBlockItem {
	BlockItem
}

pub fn new_gold_block_item() GoldBlockItem {
	return GoldBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:gold_block'
			block_runtime: world.gold_block.network_id
		}
	}
}
