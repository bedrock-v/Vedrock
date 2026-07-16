module item

import server.world

// CobbledDeepslateItem is the block-item for 'minecraft:cobbled_deepslate'.
pub struct CobbledDeepslateItem {
	BlockItem
}

pub fn new_cobbled_deepslate_item() CobbledDeepslateItem {
	return CobbledDeepslateItem{
		BlockItem: BlockItem{
			id:            'minecraft:cobbled_deepslate'
			block_runtime: world.cobbled_deepslate.network_id
		}
	}
}
