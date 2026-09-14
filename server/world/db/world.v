module db

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
//
// Everything the server writes into the terrain travels as a column: one
// record holding a chunk footprint's block overrides and block entities. The
// bytes are opaque here, which keeps a backend to storing and returning them
// and keeps their meaning in one place (encode_column).
pub interface Provider {
	dimension() world.Dimension
	load_chunk(cx int, cz int) ?world.Chunk
	// load_column returns one column's record or none when the world has
	// stored nothing in that footprint. Columns are read one at a time and on
	// demand. It keeps resident memory tied to the area in play
	// rather than to how much the world has ever been edited.
	load_column(cx int, cz int) ?[]u8
	// each_player_spawn walks the beds players have bound themselves to in
	// this world. key is whatever the caller identifies a player by.
	each_player_spawn(cb fn (key string, x int, y int, z int))
mut:
	store_column(cx int, cz int, data []u8) !
	store_chunk_blocks(cx int, cz int, encoded map[int][]u8) !
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
	overrides := open_leveldb(path + '_overrides')!
	vanilla := open_leveldb(path) or {
		overrides.close() or {}
		return err
	}
	migrate_legacy_records(overrides) or {
		overrides.close() or {}
		vanilla.close() or {}
		return err
	}
	return &WorldStore{
		db:        vanilla
		overrides: overrides
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

fn put_i64(mut b []u8, v i64) {
	u := u64(v)
	for shift in [0, 8, 16, 24, 32, 40, 48, 56] {
		b << u8(u >> shift)
	}
}

fn read_i64(b []u8, offset int) i64 {
	mut u := u64(0)
	for i in 0 .. 8 {
		u |= u64(b[offset + i]) << (i * 8)
	}
	return i64(u)
}

// column_record_key is 9 bytes where every legacy position key below is 13,
// which is what lets both shapes sit in one LevelDB handle while a world is
// being migrated.
fn column_record_key(cx int, cz int) []u8 {
	mut b := []u8{}
	b << u8(`C`)
	put_i32(mut b, cx)
	put_i32(mut b, cz)
	return b
}

// player_spawn_key is the one key here that is not a position. The player key
// is variable length which is also what keeps it clear of the position keys.
fn player_spawn_key(key string) []u8 {
	mut b := []u8{}
	b << u8(`s`)
	b << key.bytes()
	return b
}

pub fn (w &WorldStore) store_column(cx int, cz int, data []u8) ! {
	w.overrides.put(column_record_key(cx, cz), data)!
}

pub fn (w &WorldStore) load_column(cx int, cz int) ?[]u8 {
	return w.overrides.get(column_record_key(cx, cz))
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
