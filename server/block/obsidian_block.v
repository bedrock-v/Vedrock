module block

import server.world

// ObsidianBlock is the class for 'minecraft:obsidian'.
pub struct ObsidianBlock {
	SimpleBlock
}

// obsidian_hardness is 35 on Bedrock, not the 50 the Java edition uses. The
// two editions genuinely disagree here, so a Java sourced table gets this
// block wrong.
const obsidian_hardness = f32(35.0)

pub fn new_obsidian() ObsidianBlock {
	return ObsidianBlock{
		SimpleBlock: SimpleBlock{
			id:             'minecraft:obsidian'
			block_runtime:  world.obsidian.network_id
			break_hardness: obsidian_hardness
		}
	}
}
