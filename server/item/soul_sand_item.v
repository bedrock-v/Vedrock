module item

import server.world

// SoulSandItem is the block-item for 'minecraft:soul_sand'.
pub struct SoulSandItem {
	BlockItem
}

pub fn new_soul_sand_item() SoulSandItem {
	return SoulSandItem{
		BlockItem: BlockItem{
			id:            'minecraft:soul_sand'
			block_runtime: world.soul_sand.network_id
		}
	}
}
