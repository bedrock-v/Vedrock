module item

import server.world

// ObsidianItem is the block-item for 'minecraft:obsidian'.
pub struct ObsidianItem {
	BlockItem
}

pub fn new_obsidian_item() ObsidianItem {
	return ObsidianItem{
		BlockItem: BlockItem{
			id:            'minecraft:obsidian'
			block_runtime: world.obsidian.network_id
		}
	}
}
