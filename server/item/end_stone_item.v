module item

import server.world

// EndStoneItem is the block-item for 'minecraft:end_stone'.
pub struct EndStoneItem {
	BlockItem
}

pub fn new_end_stone_item() EndStoneItem {
	return EndStoneItem{
		BlockItem: BlockItem{
			id:            'minecraft:end_stone'
			block_runtime: world.end_stone.network_id
		}
	}
}
