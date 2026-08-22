module block

import server.world

// Shelf mushrooms grow on the side of a block in two stages. Like the wool and
// concrete shapes they are driven from the block definitions, so the client
// only knows them once the server has described them.
const shelf_mushroom_hardness = f32(0.0)

// ShelfMushroomBlock is the class for 'minecraft:shelf_mushroom'. It breaks
// instantly and takes a sword or shears the way the other fungi do.
pub struct ShelfMushroomBlock {
	SimpleBlock
}

pub fn (b ShelfMushroomBlock) tool_type() int {
	return tool_type_shears | tool_type_sword
}

pub fn (b ShelfMushroomBlock) harvest_level() int {
	return harvest_level_none
}

fn shelf_mushroom_block(growth int, direction string) Block {
	id := 'minecraft:shelf_mushroom'
	runtime := world.new_block_with_states(id, [
		world.BlockState{
			key:       'growth'
			kind:      world.state_kind_int
			int_value: growth
		},
		cardinal_direction_state(direction),
	])
	return ShelfMushroomBlock{
		SimpleBlock: SimpleBlock{
			id:             id
			block_runtime:  runtime.network_id
			break_hardness: shelf_mushroom_hardness
		}
	}
}

pub fn shelf_mushroom_blocks() []Block {
	mut result := []Block{}
	for growth in 0 .. 2 {
		for direction in cardinal_directions {
			result << shelf_mushroom_block(growth, direction)
		}
	}
	return result
}
