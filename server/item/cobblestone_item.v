module item

import server.world

// CobblestoneItem is the block-item for 'minecraft:cobblestone'.
pub struct CobblestoneItem {
	BlockItem
}

pub fn new_cobblestone_item() CobblestoneItem {
	return CobblestoneItem{
		BlockItem: BlockItem{
			id:            'minecraft:cobblestone'
			block_runtime: world.cobblestone.network_id
		}
	}
}
