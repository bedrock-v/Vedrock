module block

import server.world

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

// new_bedrock_item is the item form of 'minecraft:bedrock'.
pub fn new_bedrock_item() BlockItem {
	return BlockItem{
		id:            'minecraft:bedrock'
		block_runtime: world.bedrock.network_id
	}
}
