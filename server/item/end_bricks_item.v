module item

import server.world

// EndBricksItem is the block-item for 'minecraft:end_bricks'.
pub struct EndBricksItem {
	BlockItem
}

pub fn new_end_bricks_item() EndBricksItem {
	return EndBricksItem{
		BlockItem: BlockItem{
			id:            'minecraft:end_bricks'
			block_runtime: world.end_bricks.network_id
		}
	}
}
