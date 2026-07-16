module item

import server.world

// SmoothBasaltItem is the block-item for 'minecraft:smooth_basalt'.
pub struct SmoothBasaltItem {
	BlockItem
}

pub fn new_smooth_basalt_item() SmoothBasaltItem {
	return SmoothBasaltItem{
		BlockItem: BlockItem{
			id:            'minecraft:smooth_basalt'
			block_runtime: world.smooth_basalt.network_id
		}
	}
}
