module db

import os

struct BlockCollector {
mut:
	blocks map[string]int
}

fn test_world_store_roundtrip() {
	dir := os.join_path(os.temp_dir(), 'vedrock_db_test')
	os.rmdir_all(dir) or {}
	mut store := open_world(dir) or { panic(err) }
	store.set_block(1, 64, -3, 42)
	store.set_block(-10, 0, 7, 99)
	mut c := &BlockCollector{}
	store.each_block(fn [mut c] (x int, y int, z int, runtime_id int) {
		c.blocks['${x},${y},${z}'] = runtime_id
	})
	assert c.blocks.len == 2
	assert c.blocks['1,64,-3'] == 42
	assert c.blocks['-10,0,7'] == 99
	store.close()
	mut store2 := open_world(dir) or { panic(err) }
	mut c2 := &BlockCollector{}
	store2.each_block(fn [mut c2] (x int, y int, z int, runtime_id int) {
		c2.blocks['${x},${y},${z}'] = runtime_id
	})
	assert c2.blocks.len == 2
	assert c2.blocks['1,64,-3'] == 42
	store2.close()
	os.rmdir_all(dir) or {}
}
