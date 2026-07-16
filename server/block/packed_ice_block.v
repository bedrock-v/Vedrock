module block

import server.world

// PackedIceBlock is the class for 'minecraft:packed_ice'.
pub struct PackedIceBlock {
	SimpleBlock
}

pub fn new_packed_ice() PackedIceBlock {
	return PackedIceBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:packed_ice'
			block_runtime:  world.packed_ice.network_id
			break_hardness: 0.5
		}
	}
}
