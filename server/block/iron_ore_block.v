module block

import server.world

// IronOreBlock is the class for 'minecraft:iron_ore'.
pub struct IronOreBlock {
	SimpleBlock
}

pub fn new_iron_ore() IronOreBlock {
	return IronOreBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:iron_ore'
			block_runtime:  world.iron_ore.network_id
			break_hardness: 3.0
		}
	}
}

// new_iron_ore_item is the item form of 'minecraft:iron_ore'.
pub fn new_iron_ore_item() BlockItem {
	return BlockItem{
		id:            'minecraft:iron_ore'
		block_runtime: world.iron_ore.network_id
	}
}
