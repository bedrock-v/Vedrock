module item

import server.world

// BlockItem is the base class for items that place a block when used against
// a face. It carries the block runtime id the session should set in the
// world. Concrete block items embed it, one class per block item.
pub struct BlockItem {
pub:
	id            string
	block_runtime int
}

pub fn (i BlockItem) identifier() string {
	return i.id
}

pub fn (i BlockItem) max_stack_size() int {
	return 64
}

pub fn (i BlockItem) attack_damage() f32 {
	return 0
}

pub fn (i BlockItem) nutrition() int {
	return 0
}

pub fn (i BlockItem) saturation() f32 {
	return 0
}

pub fn (i BlockItem) block_runtime_id() int {
	return i.block_runtime
}

// StoneItem is the class for 'minecraft:stone'.
pub struct StoneItem {
	BlockItem
}

pub fn new_stone_item() StoneItem {
	return StoneItem{
		BlockItem: BlockItem{
			id:            'minecraft:stone'
			block_runtime: world.stone.network_id
		}
	}
}

// DirtItem is the class for 'minecraft:dirt'.
pub struct DirtItem {
	BlockItem
}

pub fn new_dirt_item() DirtItem {
	return DirtItem{
		BlockItem: BlockItem{
			id:            'minecraft:dirt'
			block_runtime: world.dirt.network_id
		}
	}
}

// GrassBlockItem is the class for 'minecraft:grass_block'.
pub struct GrassBlockItem {
	BlockItem
}

pub fn new_grass_block_item() GrassBlockItem {
	return GrassBlockItem{
		BlockItem: BlockItem{
			id:            'minecraft:grass_block'
			block_runtime: world.grass_block.network_id
		}
	}
}

// BedrockItem is the class for 'minecraft:bedrock'.
pub struct BedrockItem {
	BlockItem
}

pub fn new_bedrock_item() BedrockItem {
	return BedrockItem{
		BlockItem: BlockItem{
			id:            'minecraft:bedrock'
			block_runtime: world.bedrock.network_id
		}
	}
}
