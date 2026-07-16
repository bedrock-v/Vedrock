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
