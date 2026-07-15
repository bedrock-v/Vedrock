module block

import server.world

// EmeraldOreBlock is the class for 'minecraft:emerald_ore'.
pub struct EmeraldOreBlock {
	SimpleBlock
}

pub fn new_emerald_ore() EmeraldOreBlock {
	return EmeraldOreBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:emerald_ore'
			block_runtime:  world.emerald_ore.network_id
			break_hardness: 3.0
		}
	}
}
