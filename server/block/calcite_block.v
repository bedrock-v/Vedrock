module block

import server.world

// CalciteBlock is the class for 'minecraft:calcite'.
pub struct CalciteBlock {
	SimpleBlock
}

pub fn new_calcite() CalciteBlock {
	return CalciteBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:calcite'
			block_runtime:  world.calcite.network_id
			break_hardness: 0.75
		}
	}
}

// new_calcite_item is the item form of 'minecraft:calcite'.
pub fn new_calcite_item() BlockItem {
	return BlockItem{
		id:            'minecraft:calcite'
		block_runtime: world.calcite.network_id
	}
}
