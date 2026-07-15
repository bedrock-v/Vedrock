module item

import server.world

// CopperOreItem is the block-item for 'minecraft:copper_ore'.
pub struct CopperOreItem {
	BlockItem
}

pub fn new_copper_ore_item() CopperOreItem {
	return CopperOreItem{
		BlockItem: BlockItem{
			id:            'minecraft:copper_ore'
			block_runtime: world.copper_ore.network_id
		}
	}
}
