module item

import server.world

// EmeraldOreItem is the block-item for 'minecraft:emerald_ore'.
pub struct EmeraldOreItem {
	BlockItem
}

pub fn new_emerald_ore_item() EmeraldOreItem {
	return EmeraldOreItem{
		BlockItem: BlockItem{
			id:            'minecraft:emerald_ore'
			block_runtime: world.emerald_ore.network_id
		}
	}
}
