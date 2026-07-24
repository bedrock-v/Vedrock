module item

import server.world

// LapisOreItem is the block-item for 'minecraft:lapis_ore'.
pub struct LapisOreItem {
	BlockItem
}

pub fn new_lapis_ore_item() LapisOreItem {
	return LapisOreItem{
		BlockItem: BlockItem{
			id:            'minecraft:lapis_ore'
			block_runtime: world.lapis_ore.network_id
		}
	}
}
