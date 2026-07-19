module db

import sync
import server.world

// World is a single loaded world - its persistent store plus the in-memory
// cache of block overrides layered on top of the generated/vanilla chunks.
@[heap]
pub struct World {
pub:
	name      string
	dimension world.Dimension = world.overworld
mut:
	store        &WorldStore = unsafe { nil }
	overrides    map[string]int
	tile_data    map[string]TileData
	mutex        &sync.Mutex = sync.new_mutex()
	current_tick i64
	scheduled    []ScheduledEntry
pub mut:
	generator_name string
}

pub struct BlockOverride {
pub:
	x  int
	y  int
	z  int
	id int
}

// TileData is a block-entity's persistent data at a position.
pub struct TileData {
pub mut:
	text string
}

// TileEntry is a TileData paired with its position, returned by
// tile_entries_in_chunk for chunk-send enrichment.
pub struct TileEntry {
pub:
	x    int
	y    int
	z    int
	text string
}

fn override_key(x int, y int, z int) string {
	return '${x}:${y}:${z}'
}

pub fn new_world(name string, store &WorldStore, generator_name string, dim world.Dimension) &World {
	return &World{
		name:           name
		dimension:      dim
		store:          store
		mutex:          sync.new_mutex()
		generator_name: generator_name
	}
}

// load pulls every persisted block override and tile data entry into the
// in-memory cache.
pub fn (mut w World) load() {
	if isnil(w.store) {
		return
	}
	w.store.each_block(fn [mut w] (x int, y int, z int, runtime_id int) {
		w.overrides[override_key(x, y, z)] = runtime_id
	})
	w.store.each_tile(fn [mut w] (x int, y int, z int, text string) {
		w.tile_data[override_key(x, y, z)] = TileData{
			text: text
		}
	})
}

pub fn (mut w World) set_block(x int, y int, z int, runtime_id int) {
	w.mutex.lock()
	w.overrides[override_key(x, y, z)] = runtime_id
	w.mutex.unlock()
	if !isnil(w.store) {
		w.store.set_block(x, y, z, runtime_id)
	}
}

pub fn (w &World) block_override(x int, y int, z int) ?int {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return w.overrides[override_key(x, y, z)] or { return none }
}

pub fn (w &World) block_count() int {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return w.overrides.len
}

pub fn (w &World) overrides_in_chunk(cx int, cz int) []BlockOverride {
	mut out := []BlockOverride{}
	mut m := w.mutex
	m.lock()
	for key, id in w.overrides {
		parts := key.split(':')
		if parts.len != 3 {
			continue
		}
		x := parts[0].int()
		z := parts[2].int()
		if (x >> 4) == cx && (z >> 4) == cz {
			out << BlockOverride{
				x:  x
				y:  parts[1].int()
				z:  z
				id: id
			}
		}
	}
	m.unlock()
	return out
}

// set_tile_text stores a position's tile text, writing through to the store the same way set_block does.
pub fn (mut w World) set_tile_text(x int, y int, z int, text string) {
	w.mutex.lock()
	w.tile_data[override_key(x, y, z)] = TileData{
		text: text
	}
	w.mutex.unlock()
	if !isnil(w.store) {
		w.store.set_tile_text(x, y, z, text)
	}
}

pub fn (w &World) tile_text(x int, y int, z int) ?string {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	td := w.tile_data[override_key(x, y, z)] or { return none }
	return td.text
}

pub fn (w &World) tile_entries_in_chunk(cx int, cz int) []TileEntry {
	mut out := []TileEntry{}
	mut m := w.mutex
	m.lock()
	for key, td in w.tile_data {
		parts := key.split(':')
		if parts.len != 3 {
			continue
		}
		x := parts[0].int()
		z := parts[2].int()
		if (x >> 4) == cx && (z >> 4) == cz {
			out << TileEntry{
				x:    x
				y:    parts[1].int()
				z:    z
				text: td.text
			}
		}
	}
	m.unlock()
	return out
}

// make_generator wraps the given fallback with a StoredGenerator when this
// world has a backing store, so saved chunks are served before the fallback.
pub fn (w &World) make_generator(fallback world.Generator) world.Generator {
	if isnil(w.store) {
		return fallback
	}
	return new_stored_generator(w.store, fallback)
}

// flush persists this world's store to disk without unloading it. Safe to call
// while the world is live - it does not touch the in-memory override cache.
pub fn (mut w World) flush() {
	if !isnil(w.store) {
		w.store.flush()
	}
}

pub fn (mut w World) close() {
	if !isnil(w.store) {
		w.store.close()
	}
}
