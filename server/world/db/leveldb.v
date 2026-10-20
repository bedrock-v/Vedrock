module db

import leveldb

@[heap]
pub struct LevelDB {
mut:
	db &leveldb.DB
}

pub fn open_leveldb(path string) !&LevelDB {
	ldb := leveldb.open(path, leveldb.Options{}) or { return error('leveldb open failed: ${err}') }
	return &LevelDB{
		db: ldb
	}
}

// put returns write failures to the caller instead of discarding them,
// allowing persistence code to distinguish rejected writes from success.
pub fn (l &LevelDB) put(key []u8, value []u8) ! {
	mut ldb := unsafe { l.db }
	ldb.put(key, value, leveldb.WriteOptions{}) or { return error('leveldb put failed: ${err}') }
}

// KeyValue is one record for put_all.
pub struct KeyValue {
pub:
	key   []u8
	value []u8
}

// put_all writes every record as a single batch. The batch reaches the journal
// as one append which is both cheaper than the individual puts and the reason
// a reader never finds half of it.
pub fn (l &LevelDB) put_all(records []KeyValue) ! {
	if records.len == 0 {
		return
	}
	mut ldb := unsafe { l.db }
	mut batch := leveldb.new_batch()
	for record in records {
		batch.put(record.key, record.value)
	}
	ldb.write(mut batch, leveldb.WriteOptions{}) or {
		return error('leveldb batch write failed: ${err}')
	}
}

pub fn (l &LevelDB) get(key []u8) ?[]u8 {
	mut ldb := unsafe { l.db }
	return ldb.get(key, leveldb.ReadOptions{})
}

pub fn (l &LevelDB) delete(key []u8) ! {
	mut ldb := unsafe { l.db }
	ldb.delete(key, leveldb.WriteOptions{}) or { return error('leveldb delete failed: ${err}') }
}

pub fn (l &LevelDB) each(cb fn (key []u8, value []u8)) {
	mut ldb := unsafe { l.db }
	mut it := ldb.new_iterator(leveldb.ReadOptions{}) or { return }
	for ok := it.first(); ok; ok = it.next() {
		cb(it.key(), it.value())
	}
}

// flush forces pending writes down to the device without releasing the handle,
// so a crash after a flush can't lose the flushed data. close() already syncs,
// so this is only needed for periodic mid-run durability.
//
// It syncs the journal rather than compacting. Compaction rewrites the
// memtable into a table file, costing far more and buys no durability the
// journal does not already give: a crash is recovered from the journal either
// way.
pub fn (l &LevelDB) flush() ! {
	mut ldb := unsafe { l.db }
	ldb.sync() or { return error('leveldb sync failed: ${err}') }
}

pub fn (l &LevelDB) close() ! {
	mut ldb := unsafe { l.db }
	ldb.close() or { return error('leveldb close failed: ${err}') }
}
