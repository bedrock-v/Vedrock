module db

import leveldb

@[heap]
pub struct LevelDB {
mut:
	db &leveldb.DB
}

pub fn open_leveldb(path string) !&LevelDB {
	ldb := leveldb.open(path, leveldb.Options{}) or {
		return error('leveldb open failed: ${err}')
	}
	return &LevelDB{
		db: ldb
	}
}

pub fn (l &LevelDB) put(key []u8, value []u8) {
	mut ldb := unsafe { l.db }
	ldb.put(key, value, leveldb.WriteOptions{}) or {}
}

pub fn (l &LevelDB) get(key []u8) ?[]u8 {
	mut ldb := unsafe { l.db }
	return ldb.get(key, leveldb.ReadOptions{})
}

pub fn (l &LevelDB) delete(key []u8) {
	mut ldb := unsafe { l.db }
	ldb.delete(key, leveldb.WriteOptions{}) or {}
}

pub fn (l &LevelDB) each(cb fn (key []u8, value []u8)) {
	mut ldb := unsafe { l.db }
	mut it := ldb.new_iterator(leveldb.ReadOptions{}) or { return }
	for ok := it.first(); ok; ok = it.next() {
		cb(it.key(), it.value())
	}
}

pub fn (l &LevelDB) close() {
	mut ldb := unsafe { l.db }
	ldb.close() or {}
}
