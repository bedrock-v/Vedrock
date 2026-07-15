module item

import server.world

// SandstoneItem is the block-item for 'minecraft:sandstone'.
pub struct SandstoneItem {
	BlockItem
}

pub fn new_sandstone_item() SandstoneItem {
	return SandstoneItem{
		BlockItem: BlockItem{
			id:            'minecraft:sandstone'
			block_runtime: world.sandstone.network_id
		}
	}
}
