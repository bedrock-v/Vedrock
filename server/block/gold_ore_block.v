module block

import server.world

// GoldOreBlock is the class for 'minecraft:gold_ore'.
pub struct GoldOreBlock {
	SimpleBlock
}

pub fn new_gold_ore() GoldOreBlock {
	return GoldOreBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:gold_ore'
			block_runtime:  world.gold_ore.network_id
			break_hardness: 3.0
		}
	}
}
