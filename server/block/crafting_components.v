module block

import server.world

const crafting_table_hardness = f32(2.5)

// CraftingTableBlock is the crafting table (workbench) block. Its interact
// behaviour is handled by the session layer, which detects it by type and
// opens the 3x3 crafting container.
pub struct CraftingTableBlock {
	SimpleBlock
}

pub fn new_crafting_table() Block {
	id := 'minecraft:crafting_table'
	return Block(CraftingTableBlock{
		SimpleBlock: SimpleBlock{
			id:             id
			block_runtime:  world.new_block(id).network_id
			break_hardness: crafting_table_hardness
		}
	})
}
