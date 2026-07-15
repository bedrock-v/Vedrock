module item

import server.world

// RedstoneOreItem is the block-item for 'minecraft:redstone_ore'.
pub struct RedstoneOreItem {
	BlockItem
}

pub fn new_redstone_ore_item() RedstoneOreItem {
	return RedstoneOreItem{
		BlockItem: BlockItem{
			id:            'minecraft:redstone_ore'
			block_runtime: world.redstone_ore.network_id
		}
	}
}
