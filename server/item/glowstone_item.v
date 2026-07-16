module item

import server.world

// GlowstoneItem is the block-item for 'minecraft:glowstone'.
pub struct GlowstoneItem {
	BlockItem
}

pub fn new_glowstone_item() GlowstoneItem {
	return GlowstoneItem{
		BlockItem: BlockItem{
			id:            'minecraft:glowstone'
			block_runtime: world.glowstone.network_id
		}
	}
}
