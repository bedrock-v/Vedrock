module storage

import os

#flag -lleveldb
#include <leveldb/c.h>

@[typedef]
struct C.leveldb_t {}

@[typedef]
struct C.leveldb_options_t {}

@[typedef]
struct C.leveldb_readoptions_t {}

@[typedef]
struct C.leveldb_writeoptions_t {}

@[typedef]
struct C.leveldb_iterator_t {}

fn C.leveldb_options_create() &C.leveldb_options_t
fn C.leveldb_options_set_create_if_missing(&C.leveldb_options_t, u8)
fn C.leveldb_options_set_compression(&C.leveldb_options_t, int)
fn C.leveldb_options_destroy(&C.leveldb_options_t)
fn C.leveldb_open(&C.leveldb_options_t, &char, &&char) &C.leveldb_t
fn C.leveldb_close(&C.leveldb_t)
fn C.leveldb_writeoptions_create() &C.leveldb_writeoptions_t
fn C.leveldb_readoptions_create() &C.leveldb_readoptions_t
fn C.leveldb_put(&C.leveldb_t, &C.leveldb_writeoptions_t, &char, usize, &char, usize, &&char)
fn C.leveldb_create_iterator(&C.leveldb_t, &C.leveldb_readoptions_t) &C.leveldb_iterator_t
fn C.leveldb_iter_seek_to_first(&C.leveldb_iterator_t)
fn C.leveldb_iter_valid(&C.leveldb_iterator_t) u8
fn C.leveldb_iter_next(&C.leveldb_iterator_t)
fn C.leveldb_iter_key(&C.leveldb_iterator_t, &usize) &char
fn C.leveldb_iter_value(&C.leveldb_iterator_t, &usize) &char
fn C.leveldb_iter_destroy(&C.leveldb_iterator_t)
fn C.leveldb_free(voidptr)

pub struct LevelDB {
	db       &C.leveldb_t
	woptions &C.leveldb_writeoptions_t
	roptions &C.leveldb_readoptions_t
}

pub fn open_leveldb(path string) !&LevelDB {
	os.mkdir_all(path)!
	opts := C.leveldb_options_create()
	C.leveldb_options_set_create_if_missing(opts, 1)
	C.leveldb_options_set_compression(opts, 0)
	mut err := &char(unsafe { nil })
	db := C.leveldb_open(opts, &char(path.str), &err)
	C.leveldb_options_destroy(opts)
	if !isnil(err) {
		msg := unsafe { cstring_to_vstring(err) }
		C.leveldb_free(err)
		return error('leveldb open failed: ${msg}')
	}
	return &LevelDB{
		db:       db
		woptions: C.leveldb_writeoptions_create()
		roptions: C.leveldb_readoptions_create()
	}
}

pub fn (l &LevelDB) put(key []u8, value []u8) {
	mut err := &char(unsafe { nil })
	C.leveldb_put(l.db, l.woptions, &char(key.data), usize(key.len), &char(value.data),
		usize(value.len), &err)
	if !isnil(err) {
		C.leveldb_free(err)
	}
}

pub fn (l &LevelDB) each(cb fn (key []u8, value []u8)) {
	it := C.leveldb_create_iterator(l.db, l.roptions)
	C.leveldb_iter_seek_to_first(it)
	for C.leveldb_iter_valid(it) != 0 {
		mut klen := usize(0)
		kptr := C.leveldb_iter_key(it, &klen)
		mut vlen := usize(0)
		vptr := C.leveldb_iter_value(it, &vlen)
		key := unsafe { (&u8(kptr)).vbytes(int(klen)) }
		value := unsafe { (&u8(vptr)).vbytes(int(vlen)) }
		cb(key.clone(), value.clone())
		C.leveldb_iter_next(it)
	}
	C.leveldb_iter_destroy(it)
}

pub fn (l &LevelDB) close() {
	C.leveldb_close(l.db)
}
