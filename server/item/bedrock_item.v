module item

import server.world

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
