module item

import server.world

// DiamondOreItem is the block-item for 'minecraft:diamond_ore'.
pub struct DiamondOreItem {
	BlockItem
}

pub fn new_diamond_ore_item() DiamondOreItem {
	return DiamondOreItem{
		BlockItem: BlockItem{
			id:            'minecraft:diamond_ore'
			block_runtime: world.diamond_ore.network_id
		}
	}
}
