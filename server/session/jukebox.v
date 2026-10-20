module session

import bedrock_v.nbt
import bedrock_v.protocol.types
import server.world.sound
import server.worldrt

const music_disc_prefix = 'minecraft:music_disc_'

// interact_jukebox inserts the held music disc or ejects the one already
// playing if a right click arrives with no disc to insert (or the jukebox
// already holds one). Like note blocks, the wire palette carries no
// per record state for 'minecraft:jukebox' (empty states compound), so the
// inserted record's item id is tracked as block entity data.
// Empty string means no record.
fn interact_jukebox(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition) {
	center := types.Vector3{f32(pos.x) + 0.5, f32(pos.y) + 0.5, f32(pos.z) + 0.5}
	current := tx.wr.world.tile_text(pos.x, pos.y, pos.z) or { '' }
	if current != '' {
		tx.wr.world.set_tile_text(pos.x, pos.y, pos.z, '')
		broadcast_block_entity(mut tx, pos, build_jukebox_nbt(pos.x, pos.y, pos.z, ''))
		spawn_dropped_item_stack(mut tx, current, 1, center)
		return
	}
	_, name := s.held_stack_and_name()
	if !name.starts_with(music_disc_prefix) {
		return
	}
	consume_held_item(mut s)
	tx.wr.world.set_tile_text(pos.x, pos.y, pos.z, name)
	broadcast_block_entity(mut tx, pos, build_jukebox_nbt(pos.x, pos.y, pos.z, name))
	play_sound(mut tx, center, sound.Record{ track: name.trim_string_left(music_disc_prefix) })
}

fn drop_jukebox_disc(mut tx worldrt.WorldTx, x int, y int, z int) {
	current := tx.wr.world.tile_text(x, y, z) or { return }
	if current == '' {
		return
	}
	center := types.Vector3{f32(x) + 0.5, f32(y) + 0.5, f32(z) + 0.5}
	spawn_dropped_item_stack(mut tx, current, 1, center)
	tx.wr.world.set_tile_text(x, y, z, '')
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
