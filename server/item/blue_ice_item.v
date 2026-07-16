module item

import server.world

// BlueIceItem is the block-item for 'minecraft:blue_ice'.
pub struct BlueIceItem {
	BlockItem
}

pub fn new_blue_ice_item() BlueIceItem {
	return BlueIceItem{
		BlockItem: BlockItem{
			id:            'minecraft:blue_ice'
			block_runtime: world.blue_ice.network_id
		}
	}
}
