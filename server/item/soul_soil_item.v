module item

import server.world

// SoulSoilItem is the block-item for 'minecraft:soul_soil'.
pub struct SoulSoilItem {
	BlockItem
}

pub fn new_soul_soil_item() SoulSoilItem {
	return SoulSoilItem{
		BlockItem: BlockItem{
			id:            'minecraft:soul_soil'
			block_runtime: world.soul_soil.network_id
		}
	}
}
