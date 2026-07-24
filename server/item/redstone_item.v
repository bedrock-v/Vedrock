module item

import server.world

// RedstoneItem is the class for 'minecraft:redstone' (redstone dust).
pub struct RedstoneItem {
	BlockItem
}

pub fn new_redstone() RedstoneItem {
	runtime := world.new_block_with_states('minecraft:redstone_wire', [
		world.BlockState{
			key:       'redstone_signal'
			kind:      world.state_kind_int
			int_value: 0
		},
	])
	return RedstoneItem{
		BlockItem: BlockItem{
			id:            'minecraft:redstone'
			block_runtime: runtime.network_id
		}
	}
}
