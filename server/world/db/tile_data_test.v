module db

import os
import server.world

fn test_world_tile_text_and_entries_in_chunk() {
	mut w := new_world('test', none, 'flat', world.overworld)
	w.set_tile_text(1, 5, 2, 'Front line 1')
	w.set_tile_text(20, 5, 2, 'Other chunk')

	assert w.tile_text(1, 5, 2) or { '' } == 'Front line 1'
	if _ := w.tile_text(99, 99, 99) {
		assert false
	}

	entries := w.tile_entries_in_chunk(0, 0)
	assert entries.len == 1
	assert entries[0].x == 1
	assert entries[0].y == 5
	assert entries[0].z == 2
	assert entries[0].text == 'Front line 1'

	other_chunk := w.tile_entries_in_chunk(1, 0)
	assert other_chunk.len == 1
	assert other_chunk[0].x == 20
}

fn test_world_load_restores_tile_data() {
	dir := os.join_path(os.temp_dir(), 'vedrock_tile_load_test')
	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
	mut store := open_world(dir, world.overworld) or { panic(err) }
	mut w := new_world('test', store, 'flat', world.overworld)
	w.load()
	w.set_tile_text(3, 4, 5, 'Persisted')
	w.close() or { panic(err) }

	mut store2 := open_world(dir, world.overworld) or { panic(err) }
	mut back := new_world('test', store2, 'flat', world.overworld)
	back.load()
	assert back.tile_text(3, 4, 5) or { '' } == 'Persisted'
	back.close() or { panic(err) }

	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
}
