module item

import server.world

// GoldOreItem is the block-item for 'minecraft:gold_ore'.
pub struct GoldOreItem {
	BlockItem
}

pub fn new_gold_ore_item() GoldOreItem {
	return GoldOreItem{
		BlockItem: BlockItem{
			id:            'minecraft:gold_ore'
			block_runtime: world.gold_ore.network_id
		}
	}
}
