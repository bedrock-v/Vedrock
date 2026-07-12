module item

import server.world

// MossyCobblestoneItem is the block-item for 'minecraft:mossy_cobblestone'.
pub struct MossyCobblestoneItem {
	BlockItem
}

pub fn new_mossy_cobblestone_item() MossyCobblestoneItem {
	return MossyCobblestoneItem{
		BlockItem: BlockItem{
			id:            'minecraft:mossy_cobblestone'
			block_runtime: world.mossy_cobblestone.network_id
		}
	}
}
