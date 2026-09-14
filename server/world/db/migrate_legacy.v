module db

import json2
import bedrock_v.nbt

// Before columns, a world kept one record per block override and one per block
// entity, all keyed by absolute position: 'b' for a block id, 'e' for a merged
// block entity and beneath that the two shapes block entities were originally
// split across, 't' for a sign's text as raw bytes and 'c' for a container's
// contents as JSON. Nothing writes any of them.
//
// migrate_legacy_records folds whatever a world still holds in those shapes
// into column records the first time it is opened, then deletes them. It runs
// before the store is handed out, so no write can race it.
fn migrate_legacy_records(db &LevelDB) ! {
	mut found := &LegacyRecords{}
	db.each(fn [mut found] (key []u8, value []u8) {
		found.take(key, value)
	})
	if found.keys.len == 0 {
		return
	}
	for key, mut col in found.columns {
		cx, cz := column_coords(key)
		// A column record already present is newer than any legacy record at
		// the same coordinates, it goes over the legacy data rather than
		// under it. That is also what makes a migration interrupted partway
		// safe to repeat: a column already written stays as written.
		if existing := db.get(column_record_key(cx, cz)) {
			if current := decode_column(existing) {
				for local, id in current.blocks {
					col.blocks[local] = id
				}
				for local, data in current.block_entities {
					col.block_entities[local] = data
				}
			}
		}
		db.put(column_record_key(cx, cz), encode_column(col))!
	}
	for key in found.keys {
		db.delete(key)!
	}
	db.flush()!
}

// LegacyRecords accumulates a migration in progress. It is a heap struct
// because the iteration closure above captures it.
@[heap]
struct LegacyRecords {
mut:
	columns map[i64]&Column
	// authoritative marks positions a merged 'e' record supplied. The two
	// older block entity shapes are not allowed to overwrite those and key
	// order alone does not settle it: 'e' sorts after 'c' but before 't'.
	authoritative map[string]bool
	keys          [][]u8
}

fn (mut r LegacyRecords) take(key []u8, value []u8) {
	if key.len != 13 {
		return
	}
	x, y, z := read_i32(key, 1), read_i32(key, 5), read_i32(key, 9)
	match rune(key[0]) {
		`b` {
			if value.len != 4 {
				return
			}
			mut col := r.column(x, z)
			col.blocks[local_key(x, y, z)] = read_i32(value, 0)
		}
		`e` {
			data := decode_block_entity(value) or { return }
			r.set_block_entity(x, y, z, data)
			r.authoritative[override_key(x, y, z)] = true
		}
		`t` {
			if r.authoritative[override_key(x, y, z)] {
				return
			}
			mut c := nbt.new_compound()
			c.set(block_entity_text_key, nbt.Tag(value.bytestr()))
			r.set_block_entity(x, y, z, c)
		}
		`c` {
			if r.authoritative[override_key(x, y, z)] {
				return
			}
			items := json2.decode[[]ContainerSlotItem](value.bytestr()) or { return }
			mut c := nbt.new_compound()
			c.set(block_entity_items_key, items_tag(items))
			r.set_block_entity(x, y, z, c)
		}
		else {
			return
		}
	}
	r.keys << key.clone()
}

fn (mut r LegacyRecords) set_block_entity(x int, y int, z int, data nbt.Compound) {
	mut col := r.column(x, z)
	col.block_entities[local_key(x, y, z)] = data
}

fn (mut r LegacyRecords) column(x int, z int) &Column {
	key := column_key_of(x, z)
	if col := r.columns[key] {
		return col
	}
	col := &Column{}
	r.columns[key] = col
	return col
}
