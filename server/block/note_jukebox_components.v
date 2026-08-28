module block

import server.world

const noteblock_hardness = f32(0.8)
const jukebox_hardness = f32(2.0)

pub struct NoteBlock {
	SimpleBlock
}

fn note_block() Block {
	id := 'minecraft:noteblock'
	return NoteBlock{
		SimpleBlock: SimpleBlock{
			id:             id
			block_runtime:  world.new_block(id).network_id
			break_hardness: noteblock_hardness
		}
	}
}

pub struct JukeboxBlock {
	SimpleBlock
}

fn jukebox_block() Block {
	id := 'minecraft:jukebox'
	return JukeboxBlock{
		SimpleBlock: SimpleBlock{
			id:             id
			block_runtime:  world.new_block(id).network_id
			break_hardness: jukebox_hardness
		}
	}
}

pub fn note_jukebox_blocks() []Block {
	return [note_block(), jukebox_block()]
}
