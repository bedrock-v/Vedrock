module db

import json2
import server.world

pub struct ContainerSlotItem {
pub mut:
	slot             int
	id               int
	meta             int
	count            int
	block_runtime_id int
	raw_extra_data   []u8
}

// Provider is the storage backend contract a world needs, the same shape
// WorldStore (LevelDB) already implements, extracted so a framework user can
// bring their own backend instead of being stuck with LevelDB.
pub interface Provider {
	dimension() world.Dimension
	load_chunk(cx int, cz int) ?world.Chunk
	each_block(cb fn (x int, y int, z int, runtime_id int))
	// each_block_entity walks every block that carries more than a block id:
	// a sign's text, a chest's contents, whatever a later kind needs. One
	// callback for every kind, so a new kind costs no new method here.
	each_block_entity(cb fn (x int, y int, z int, data []u8))
	// each_player_spawn walks the beds players have bound themselves to in
	// this world. key is whatever the caller identifies a player by.
	each_player_spawn(cb fn (key string, x int, y int, z int))
mut:
	set_block(x int, y int, z int, runtime_id int) !
	set_block_entity(x int, y int, z int, data []u8) !
	set_player_spawn(key string, x int, y int, z int) !
	flush() !
	close() !
}

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

pub fn (w &WorldStore) dimension() world.Dimension {
	return w.dimension
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

// block_entity_key uses the same 13-byte x/y/z layout as block_key with its own
// prefix byte, so block entity data safely coexists with block overrides in the
// same LevelDB handle.
fn block_entity_key(x int, y int, z int) []u8 {
	mut b := []u8{}
	b << u8(`e`)
	put_i32(mut b, x)
	put_i32(mut b, y)
	put_i32(mut b, z)
	return b
}

// tile_key and container_key are the two records block entities used to be
// split across. Nothing writes them any more; each_block_entity still reads
// them so a world written before the two were merged still opens.
fn tile_key(x int, y int, z int) []u8 {
	mut b := []u8{}
	b << u8(`t`)
	put_i32(mut b, x)
	put_i32(mut b, y)
	put_i32(mut b, z)
	return b
}

// player_spawn_key is the one key here that is not a position. The player key
// is variable length which is also what keeps it clear of the 13 byte
// position keys above.
fn player_spawn_key(key string) []u8 {
	mut b := []u8{}
	b << u8(`s`)
	b << key.bytes()
	return b
}

fn container_key(x int, y int, z int) []u8 {
	mut b := []u8{}
	b << u8(`c`)
	put_i32(mut b, x)
	put_i32(mut b, y)
	put_i32(mut b, z)
	return b
}

pub fn (w &WorldStore) set_block(x int, y int, z int, runtime_id int) ! {
	mut v := []u8{}
	put_i32(mut v, runtime_id)
	w.overrides.put(block_key(x, y, z), v)!
}

pub fn (w &WorldStore) each_block(cb fn (x int, y int, z int, runtime_id int)) {
	w.overrides.each(fn [cb] (key []u8, value []u8) {
		if key.len != 13 || value.len != 4 || key[0] != u8(`b`) {
			return
		}
		cb(read_i32(key, 1), read_i32(key, 5), read_i32(key, 9), read_i32(value, 0))
	})
}

pub fn (w &WorldStore) set_block_entity(x int, y int, z int, data []u8) ! {
	w.overrides.put(block_entity_key(x, y, z), data)!
}

// each_block_entity walks the merged records first, then the two legacy shapes.
// A position written under both is reported once, by the merged record, because
// that is the one anything still writes.
pub fn (w &WorldStore) each_block_entity(cb fn (x int, y int, z int, data []u8)) {
	mut seen := &PositionSet{}
	w.overrides.each(fn [cb, mut seen] (key []u8, value []u8) {
		if key.len != 13 || key[0] != u8(`e`) {
			return
		}
		x, y, z := read_i32(key, 1), read_i32(key, 5), read_i32(key, 9)
		seen.add(x, y, z)
		cb(x, y, z, value)
	})
	w.overrides.each(fn [cb, mut seen] (key []u8, value []u8) {
		if key.len != 13 || key[0] != u8(`t`) {
			return
		}
		x, y, z := read_i32(key, 1), read_i32(key, 5), read_i32(key, 9)
		if seen.has(x, y, z) {
			return
		}
		seen.add(x, y, z)
		cb(x, y, z, legacy_text_bytes(value.bytestr()))
	})
	w.overrides.each(fn [cb, mut seen] (key []u8, value []u8) {
		if key.len != 13 || key[0] != u8(`c`) {
			return
		}
		x, y, z := read_i32(key, 1), read_i32(key, 5), read_i32(key, 9)
		if seen.has(x, y, z) {
			return
		}
		items := json2.decode[[]ContainerSlotItem](value.bytestr()) or { return }
		cb(x, y, z, legacy_items_bytes(items))
	})
}

// PositionSet is a heap set  because the closures above capture it and a
// captured value would be a copy that never leaves the callback.
@[heap]
struct PositionSet {
mut:
	seen map[string]bool
}

fn (mut s PositionSet) add(x int, y int, z int) {
	s.seen[override_key(x, y, z)] = true
}

fn (s &PositionSet) has(x int, y int, z int) bool {
	return s.seen[override_key(x, y, z)] or { false }
}

pub fn (w &WorldStore) set_player_spawn(key string, x int, y int, z int) ! {
	mut v := []u8{}
	put_i32(mut v, x)
	put_i32(mut v, y)
	put_i32(mut v, z)
	w.overrides.put(player_spawn_key(key), v)!
}

pub fn (w &WorldStore) each_player_spawn(cb fn (key string, x int, y int, z int)) {
	w.overrides.each(fn [cb] (key []u8, value []u8) {
		if key.len < 2 || value.len != 12 || key[0] != u8(`s`) {
			return
		}
		cb(key[1..].bytestr(), read_i32(value, 0), read_i32(value, 4), read_i32(value, 8))
	})
}

// flush persists both backing databases without closing them. Both are
// always attempted even if the first fails, so one handle's failure never
// leaves the other silently unflushed; the first error encountered, if any,
// is what's returned.
pub fn (w &WorldStore) flush() ! {
	mut first_err := ''
	w.db.flush() or { first_err = err.msg() }
	w.overrides.flush() or {
		if first_err == '' {
			first_err = err.msg()
		}
	}
	if first_err != '' {
		return error('worldstore flush failed: ${first_err}')
	}
}

pub fn (w &WorldStore) close() ! {
	mut first_err := ''
	w.db.close() or { first_err = err.msg() }
	w.overrides.close() or {
		if first_err == '' {
			first_err = err.msg()
		}
	}
	if first_err != '' {
		return error('worldstore close failed: ${first_err}')
	}
}
