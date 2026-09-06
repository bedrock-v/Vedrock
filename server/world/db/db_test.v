module db

import os
import server.world

struct ColumnCollector {
mut:
	columns map[string][]u8
}

fn test_world_store_column_roundtrip() {
	dir := os.join_path(os.temp_dir(), 'vedrock_db_test')
	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
	mut store := open_world(dir, world.overworld) or { panic(err) }
	mut w := new_world('roundtrip', store, 'flat', world.overworld)
	w.load()
	w.set_block(1, 64, -3, 42)
	w.set_block(-10, 0, 7, 99)
	w.close() or { panic(err) }

	mut reopened := open_world(dir, world.overworld) or { panic(err) }
	mut back := new_world('roundtrip', reopened, 'flat', world.overworld)
	back.load()
	assert back.block_override(1, 64, -3) or { 0 } == 42
	assert back.block_override(-10, 0, 7) or { 0 } == 99
	assert back.block_count() == 2
	back.close() or { panic(err) }

	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
}

fn test_a_column_is_one_record_however_many_blocks_it_holds() {
	dir := os.join_path(os.temp_dir(), 'vedrock_db_one_record_test')
	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
	mut store := open_world(dir, world.overworld) or { panic(err) }
	mut w := new_world('one-record', store, 'flat', world.overworld)
	w.load()
	w.set_block(1, 64, 1, 7)
	w.set_block(2, -40, 3, 8)
	w.set_block(300, 64, 300, 9)
	w.close() or { panic(err) }

	mut reopened := open_world(dir, world.overworld) or { panic(err) }
	mut c := &ColumnCollector{}
	reopened.each_column(fn [mut c] (cx int, cz int, data []u8) {
		c.columns['${cx},${cz}'] = data.clone()
	})
	assert c.columns.len == 2
	assert '0,0' in c.columns
	assert '18,18' in c.columns
	reopened.close() or { panic(err) }

	os.rmdir_all(dir) or {}
	os.rmdir_all(dir + '_overrides') or {}
}
