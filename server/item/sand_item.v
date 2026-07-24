module item

import server.world

// SandItem is the block-item for 'minecraft:sand'.
pub struct SandItem {
	BlockItem
}

pub fn new_sand_item() SandItem {
	return SandItem{
		BlockItem: BlockItem{
			id:            'minecraft:sand'
			block_runtime: world.sand.network_id
		}
	}
}
