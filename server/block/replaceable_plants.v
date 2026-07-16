module block

import server.world

// Plain ground cover plants that placing another block on top of should
// silently replace, rather than block the placement. The reference
// implementers for Replaceable.
const replaceable_plant_hardness = f32(0.0)

pub struct ShortGrassBlock {
	SimpleBlock
}

pub fn (b ShortGrassBlock) replaceable() bool {
	return true
}

pub fn new_short_grass_block() ShortGrassBlock {
	id := 'minecraft:short_grass'
	return ShortGrassBlock{
		SimpleBlock: SimpleBlock{
			id:             id
			block_runtime:  world.new_block(id).network_id
			break_hardness: replaceable_plant_hardness
		}
	}
}

pub struct FernBlock {
	SimpleBlock
}

pub fn (b FernBlock) replaceable() bool {
	return true
}

pub fn new_fern_block() FernBlock {
	id := 'minecraft:fern'
	return FernBlock{
		SimpleBlock: SimpleBlock{
			id:             id
			block_runtime:  world.new_block(id).network_id
			break_hardness: replaceable_plant_hardness
		}
	}
}

pub fn replaceable_plant_blocks() []Block {
	return [Block(new_short_grass_block()), new_fern_block()]
}
