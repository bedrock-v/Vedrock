module item

import server.world

// RedSandItem is the block-item for 'minecraft:red_sand'.
pub struct RedSandItem {
	BlockItem
}

pub fn new_red_sand_item() RedSandItem {
	return RedSandItem{
		BlockItem: BlockItem{
			id:            'minecraft:red_sand'
			block_runtime: world.red_sand.network_id
		}
	}
}
