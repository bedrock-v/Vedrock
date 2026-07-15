module item

import server.world

// IceItem is the block-item for 'minecraft:ice'.
pub struct IceItem {
	BlockItem
}

pub fn new_ice_item() IceItem {
	return IceItem{
		BlockItem: BlockItem{
			id:            'minecraft:ice'
			block_runtime: world.ice.network_id
		}
	}
}
