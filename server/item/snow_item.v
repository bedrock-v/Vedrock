module item

import server.world

// SnowItem is the block-item for 'minecraft:snow'.
pub struct SnowItem {
	BlockItem
}

pub fn new_snow_item() SnowItem {
	return SnowItem{
		BlockItem: BlockItem{
			id:            'minecraft:snow'
			block_runtime: world.snow.network_id
		}
	}
}
