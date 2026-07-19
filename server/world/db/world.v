module db

import server.world

@[heap]
pub struct WorldStore {
	db        &LevelDB
	overrides &LevelDB
	dimension world.Dimension = world.overworld
}

pub fn open_world(path string, dim world.Dimension) !&WorldStore {
	return &WorldStore{
		db:        open_leveldb(path)!
		overrides: open_leveldb(path + '_overrides')!
		dimension: dim
	}
}

fn put_i32(mut b []u8, v int) {
	u := u32(v)
	b << u8(u)
	b << u8(u >> 8)
	b << u8(u >> 16)
	b << u8(u >> 24)
}

fn read_i32(b []u8, offset int) int {
	return int(u32(b[offset]) | (u32(b[offset + 1]) << 8) | (u32(b[offset + 2]) << 16) | (u32(b[
		offset + 3]) << 24))
}

fn block_key(x int, y int, z int) []u8 {
	mut b := []u8{}
	b << u8(`b`)
	put_i32(mut b, x)
	put_i32(mut b, y)
	put_i32(mut b, z)
	return b
}

// tile_key uses the same 13-byte x/y/z layout as block_key with a distinct
// prefix byte ('t' instead of 'b'), so tile data safely coexists with block
// overrides in the same LevelDB handle.
fn tile_key(x int, y int, z int) []u8 {
	mut b := []u8{}
	b << u8(`t`)
	put_i32(mut b, x)
	put_i32(mut b, y)
	put_i32(mut b, z)
	return b
}

pub fn (w &WorldStore) set_block(x int, y int, z int, runtime_id int) {
	mut v := []u8{}
	put_i32(mut v, runtime_id)
	w.overrides.put(block_key(x, y, z), v)
}

pub fn (w &WorldStore) each_block(cb fn (x int, y int, z int, runtime_id int)) {
	w.overrides.each(fn [cb] (key []u8, value []u8) {
		if key.len != 13 || value.len != 4 || key[0] != u8(`b`) {
			return
		}
		cb(read_i32(key, 1), read_i32(key, 5), read_i32(key, 9), read_i32(value, 0))
	})
}

// set_tile_text persists a block-entity's tex at a position, sharing the overrides handle with a distinct key
// prefix rather than opening a third LevelDB handle for no isolation benefit.
pub fn (w &WorldStore) set_tile_text(x int, y int, z int, text string) {
	w.overrides.put(tile_key(x, y, z), text.bytes())
}

pub fn (w &WorldStore) each_tile(cb fn (x int, y int, z int, text string)) {
	w.overrides.each(fn [cb] (key []u8, value []u8) {
		if key.len != 13 || key[0] != u8(`t`) {
			return
		}
		cb(read_i32(key, 1), read_i32(key, 5), read_i32(key, 9), value.bytestr())
	})
}

// flush persists both backing databases without closing them.
pub fn (w &WorldStore) flush() {
	w.db.flush()
	w.overrides.flush()
}

pub fn (w &WorldStore) close() {
	w.db.close()
	w.overrides.close()
}
