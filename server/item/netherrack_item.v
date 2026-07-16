module item

import server.world

// NetherrackItem is the block-item for 'minecraft:netherrack'.
pub struct NetherrackItem {
	BlockItem
}

pub fn new_netherrack_item() NetherrackItem {
	return NetherrackItem{
		BlockItem: BlockItem{
			id:            'minecraft:netherrack'
			block_runtime: world.netherrack.network_id
		}
	}
}
