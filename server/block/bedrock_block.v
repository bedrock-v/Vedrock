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
