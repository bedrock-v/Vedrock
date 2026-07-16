module item

import server.world

// IronOreItem is the block-item for 'minecraft:iron_ore'.
pub struct IronOreItem {
	BlockItem
}

pub fn new_iron_ore_item() IronOreItem {
	return IronOreItem{
		BlockItem: BlockItem{
			id:            'minecraft:iron_ore'
			block_runtime: world.iron_ore.network_id
		}
	}
}
