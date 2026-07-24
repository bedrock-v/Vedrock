module item

import server.world

// PackedIceItem is the block-item for 'minecraft:packed_ice'.
pub struct PackedIceItem {
	BlockItem
}

pub fn new_packed_ice_item() PackedIceItem {
	return PackedIceItem{
		BlockItem: BlockItem{
			id:            'minecraft:packed_ice'
			block_runtime: world.packed_ice.network_id
		}
	}
}
