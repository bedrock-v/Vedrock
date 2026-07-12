module block

import server.world

// Concrete block classes, one per block. Runtime ids come from the world
// module block constants so they stay in sync with the block palette.

// StoneBlock is the class for 'minecraft:stone'.
pub struct StoneBlock {
	SimpleBlock
}

pub fn new_stone_block() StoneBlock {
	return StoneBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:stone'
			block_runtime:  world.stone.network_id
			break_hardness: 1.5
		}
	}
}

// DirtBlock is the class for 'minecraft:dirt'.
pub struct DirtBlock {
	SimpleBlock
}

pub fn new_dirt_block() DirtBlock {
	return DirtBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:dirt'
			block_runtime:  world.dirt.network_id
			break_hardness: 0.5
		}
	}
}

// GrassBlock is the class for 'minecraft:grass_block'.
pub struct GrassBlock {
	SimpleBlock
}

pub fn new_grass_block() GrassBlock {
	return GrassBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:grass_block'
			block_runtime:  world.grass_block.network_id
			break_hardness: 0.6
		}
	}
}

// BedrockBlock is the class for 'minecraft:bedrock'.
pub struct BedrockBlock {
	UnbreakableBlock
}

pub fn new_bedrock_block() BedrockBlock {
	return BedrockBlock{
		UnbreakableBlock: UnbreakableBlock{
			id:            'minecraft:bedrock'
			block_runtime: world.bedrock.network_id
		}
	}
}
