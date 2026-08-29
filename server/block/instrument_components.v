module block

import server.world

// CraftingTableBlock carries no state of its own. The grid it opens
// belongs to the player's session, not the block. See session/crafting.v.

const crafting_table_hardness = f32(2.5)

pub struct CraftingTableBlock {
	SimpleBlock
}

fn crafting_table_block() Block {
	id := 'minecraft:crafting_table'
	return CraftingTableBlock{
		SimpleBlock: SimpleBlock{
			id:             id
			block_runtime:  world.new_block(id).network_id
			break_hardness: crafting_table_hardness
		}
	}
}

pub fn crafting_table_blocks() []Block {
	return [crafting_table_block()]
}
