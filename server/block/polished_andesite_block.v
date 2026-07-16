module block

import server.world

// PolishedAndesiteBlock is the class for 'minecraft:polished_andesite'.
pub struct PolishedAndesiteBlock {
	SimpleBlock
}

pub fn new_polished_andesite() PolishedAndesiteBlock {
	return PolishedAndesiteBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:polished_andesite'
			block_runtime:  world.polished_andesite.network_id
			break_hardness: 1.5
		}
	}
}
