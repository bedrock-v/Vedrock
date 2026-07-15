module item

import server.world

// CalciteItem is the block-item for 'minecraft:calcite'.
pub struct CalciteItem {
	BlockItem
}

pub fn new_calcite_item() CalciteItem {
	return CalciteItem{
		BlockItem: BlockItem{
			id:            'minecraft:calcite'
			block_runtime: world.calcite.network_id
		}
	}
}
