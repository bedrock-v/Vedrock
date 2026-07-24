module db

import os
import server.world

struct TileCollector {
mut:
	texts map[string]string
}

struct RuntimeIdCollector {
mut:
	ids map[string]int
}

fn test_world_store_tile_text_roundtrip() {
	dir := os.join_path(os.temp_dir(), 'vedrock_tile_db_test')
	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
	mut store := open_world(dir, world.overworld) or { panic(err) }
	store.set_block(1, 64, -3, 42)
	store.set_tile_text(1, 64, -3, 'Hello')
	store.set_tile_text(5, 5, 5, 'World')
	mut c := &TileCollector{}
	store.each_tile(fn [mut c] (x int, y int, z int, text string) {
		c.texts['${x},${y},${z}'] = text
	})
	assert c.texts.len == 2
	assert c.texts['1,64,-3'] == 'Hello'
	assert c.texts['5,5,5'] == 'World'

	// each_block must ignore tile prefixed keys and vice versa.
	mut rc := &RuntimeIdCollector{}
	store.each_block(fn [mut rc] (x int, y int, z int, runtime_id int) {
		rc.ids['${x},${y},${z}'] = runtime_id
	})
	assert rc.ids.len == 1
	assert rc.ids['1,64,-3'] == 42

	store.close()
	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
}

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
	store.set_tile_text(3, 4, 5, 'Persisted')
	store.close()

	mut store2 := open_world(dir, world.overworld) or { panic(err) }
	mut w := new_world('test', store2, 'flat', world.overworld)
	w.load()
	assert w.tile_text(3, 4, 5) or { '' } == 'Persisted'
	store2.close()

	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
}
