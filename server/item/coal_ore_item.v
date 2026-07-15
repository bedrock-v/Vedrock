module item

import server.world

// CoalOreItem is the block-item for 'minecraft:coal_ore'.
pub struct CoalOreItem {
	BlockItem
}

pub fn new_coal_ore_item() CoalOreItem {
	return CoalOreItem{
		BlockItem: BlockItem{
			id:            'minecraft:coal_ore'
			block_runtime: world.coal_ore.network_id
		}
	}
}
