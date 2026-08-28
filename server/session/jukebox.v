module session

import nbt
import protocol.types
import server.world.sound
import protocol.current as proto

const music_disc_prefix = 'minecraft:music_disc_'

// interact_jukebox inserts the held music disc or ejects the one already
// playing if a right click arrives with no disc to insert (or the jukebox
// already holds one). Like note blocks, the wire palette carries no
// per record state for 'minecraft:jukebox' (empty states compound), so the
// inserted record's item id is tracked as block entity data.
// Empty string means no record.
fn (mut tx WorldTx) interact_jukebox(mut s NetworkSession, pos types.BlockPosition) {
	center := types.Vector3{f32(pos.x) + 0.5, f32(pos.y) + 0.5, f32(pos.z) + 0.5}
	current := tx.wr.world.tile_text(pos.x, pos.y, pos.z) or { '' }
	if current != '' {
		tx.wr.world.set_tile_text(pos.x, pos.y, pos.z, '')
		tx.wr.broadcast_world(&proto.BlockActorDataPacket{
			block_position:  proto.block_pos(pos)
			actor_data_tags: build_jukebox_nbt(pos.x, pos.y, pos.z, '')
		})
		spawn_dropped_item_stack(mut tx.wr, current, 1, center)
		return
	}
	_, name := s.held_stack_and_name()
	if !name.starts_with(music_disc_prefix) {
		return
	}
	tx.consume_held_item(mut s)
	tx.wr.world.set_tile_text(pos.x, pos.y, pos.z, name)
	tx.wr.broadcast_world(&proto.BlockActorDataPacket{
		block_position:  proto.block_pos(pos)
		actor_data_tags: build_jukebox_nbt(pos.x, pos.y, pos.z, name)
	})
	tx.play_sound(center, sound.Record{ track: name.trim_string_left(music_disc_prefix) })
}

fn build_jukebox_nbt(x int, y int, z int, record_item_name string) nbt.RootTag {
	mut root := nbt.new_compound()
	root.set('id', nbt.Tag('RecordPlayer'))
	root.set('x', nbt.Tag(i32(x)))
	root.set('y', nbt.Tag(i32(y)))
	root.set('z', nbt.Tag(i32(z)))
	if record_item_name != '' {
		mut record_item := nbt.new_compound()
		record_item.set('Name', nbt.Tag(record_item_name))
		record_item.set('Count', nbt.Tag(i8(1)))
		root.set('RecordItem', nbt.Tag(record_item))
	}
	return nbt.RootTag{
		name: ''
		tag:  nbt.Tag(root)
	}
}
