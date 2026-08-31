module session

import bedrock_v.nbt
import bedrock_v.protocol.types
import server.world.sound
import bedrock_v.protocol.current as proto

// note_block_pitches is the number of distinct pitches a note block cycles
// through on right click (0..24 inclusive).
const note_block_pitches = 25

// play_note advances pos's note block to its next pitch, persists that
// pitch as block entity data, broadcasts the updated block entity and
// plays the note at the block's center.
//
// minecraft:noteblock has no per pitch wire palette state, so the pitch
// must be tracked separately from the block itself.
fn (mut tx WorldTx) play_note(mut s NetworkSession, pos types.BlockPosition) {
	current := tx.wr.world.tile_text(pos.x, pos.y, pos.z) or { '0' }
	pitch := (current.int() + 1) % note_block_pitches
	tx.wr.world.set_tile_text(pos.x, pos.y, pos.z, pitch.str())
	tx.wr.broadcast_world(&proto.BlockActorDataPacket{
		block_position:  proto.block_pos(pos)
		actor_data_tags: build_note_block_nbt(pos.x, pos.y, pos.z, pitch)
	})
	center := types.Vector3{f32(pos.x) + 0.5, f32(pos.y) + 0.5, f32(pos.z) + 0.5}
	tx.play_sound(center, sound.Note{ pitch: pitch })
	tx.broadcast_swing(s)
}

fn build_note_block_nbt(x int, y int, z int, pitch int) nbt.RootTag {
	mut root := nbt.new_compound()
	root.set('id', nbt.Tag('NoteBlock'))
	root.set('x', nbt.Tag(i32(x)))
	root.set('y', nbt.Tag(i32(y)))
	root.set('z', nbt.Tag(i32(z)))
	root.set('note', nbt.Tag(i8(pitch)))
	return nbt.RootTag{
		name: ''
		tag:  nbt.Tag(root)
	}
}
