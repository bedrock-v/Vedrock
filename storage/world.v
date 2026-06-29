module storage

pub struct WorldStore {
	db &LevelDB
}

pub fn open_world(path string) !&WorldStore {
	return &WorldStore{
		db: open_leveldb(path)!
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

pub fn (w &WorldStore) set_block(x int, y int, z int, runtime_id int) {
	mut v := []u8{}
	put_i32(mut v, runtime_id)
	w.db.put(block_key(x, y, z), v)
}

pub fn (w &WorldStore) each_block(cb fn (x int, y int, z int, runtime_id int)) {
	w.db.each(fn [cb] (key []u8, value []u8) {
		if key.len != 13 || value.len != 4 || key[0] != u8(`b`) {
			return
		}
		cb(read_i32(key, 1), read_i32(key, 5), read_i32(key, 9), read_i32(value, 0))
	})
}

pub fn (w &WorldStore) close() {
	w.db.close()
}
