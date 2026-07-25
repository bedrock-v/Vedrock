module db

import sync
import server.world

// BlockPersist and TilePersist are immutable records of one write already
// applied to a World's in memory state, handed to the storage worker so the
// actual disk write never has to happen on whatever thread called
// set_block/set_tile_text. PersistBarrier lets a caller learn when the
// worker has caught up to a specific point, for flush/close. A sum type keeps these
// distinct rather than one struct with fields that are only sometimes
// meaningful.
struct BlockPersist {
	x  int
	y  int
	z  int
	id int
}

struct TilePersist {
	x    int
	y    int
	z    int
	text string
}

struct PersistBarrier {
	done chan bool
}

type PersistRecord = BlockPersist | PersistBarrier | TilePersist

// World is a single loaded world, its persistent store plus the in memory
// cache of block overrides layered on top of the generated/vanilla chunks.
//
// World writes become visible in memory immediately and reach disk
// asynchronously. flush and close wait until all previously queued writes
// have been persisted.
@[heap]
pub struct World {
pub:
	name      string
	dimension world.Dimension = world.overworld
mut:
	store        ?Provider
	overrides    map[string]int
	tile_data    map[string]TileData
	mutex        &sync.Mutex = sync.new_mutex()
	current_tick i64
	scheduled    []ScheduledEntry
	// Persistence worker state, only meaningful when store_backed is true.
	// A storeless World (tests, void worlds) never starts this thread and
	// must never send on these channels.
	store_backed  bool
	persist_queue chan PersistRecord = chan PersistRecord{cap: 4096}
	persist_stop  chan bool          = chan bool{cap: 1}
	persist_done  chan bool          = chan bool{cap: 1}
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

pub fn new_world(name string, store ?Provider, generator_name string, dim world.Dimension) &World {
	mut w := &World{
		name:           name
		dimension:      dim
		store:          store
		mutex:          sync.new_mutex()
		generator_name: generator_name
	}
	if store != none {
		w.store_backed = true
		spawn w.run_persist_worker()
	}
	return w
}

// load pulls every persisted block override and tile data entry into the
// in memory cache.
pub fn (mut w World) load() {
	store := w.store or { return }
	store.each_block(fn [mut w] (x int, y int, z int, runtime_id int) {
		w.overrides[override_key(x, y, z)] = runtime_id
	})
	store.each_tile(fn [mut w] (x int, y int, z int, text string) {
		w.tile_data[override_key(x, y, z)] = TileData{
			text: text
		}
	})
}

// set_block updates the in memory override immediately, under mutex, then
// hands the actual disk write to the storage worker rather than performing
// it here. Callers see the new value right away regardless of disk speed;
// see the World comment above for exactly what that trades away.
pub fn (mut w World) set_block(x int, y int, z int, runtime_id int) {
	w.mutex.lock()
	w.overrides[override_key(x, y, z)] = runtime_id
	w.mutex.unlock()
	w.enqueue_persist(BlockPersist{
		x:  x
		y:  y
		z:  z
		id: runtime_id
	})
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

// set_tile_text updates the in memory tile data immediately, under mutex,
// then hands the actual disk write to the storage worker. The same split
// set_block uses, and for the same reason.
pub fn (mut w World) set_tile_text(x int, y int, z int, text string) {
	w.mutex.lock()
	w.tile_data[override_key(x, y, z)] = TileData{
		text: text
	}
	w.mutex.unlock()
	w.enqueue_persist(TilePersist{
		x:    x
		y:    y
		z:    z
		text: text
	})
}

fn (mut w World) enqueue_persist(record PersistRecord) {
	if !w.store_backed {
		return
	}
	w.persist_queue <- record
}

// run_persist_worker is the storage worker: the only thread that ever calls
// store.set_block/set_tile_text, so those calls need no lock of their own
// beyond store's own internals. Started once by new_world, only when store
// is present.
fn (mut w World) run_persist_worker() {
	mut store := w.store or { return }
	for {
		select {
			record := <-w.persist_queue {
				apply_persist_record(mut store, record)
			}
			_ := <-w.persist_stop {
				// The channel is never closed, so this final non blocking
				// drain is exhaustive: shutdown only signals stop after
				// nothing more will be enqueued (see World's own close()).
				for {
					select {
						record := <-w.persist_queue {
							apply_persist_record(mut store, record)
						}
						else {
							break
						}
					}
				}
				w.persist_done <- true
				return
			}
		}
	}
}

// apply_persist_record performs the one disk write, or barrier signal, a
// single record represents.
fn apply_persist_record(mut store Provider, record PersistRecord) {
	match record {
		BlockPersist {
			store.set_block(record.x, record.y, record.z, record.id)
		}
		TilePersist {
			store.set_tile_text(record.x, record.y, record.z, record.text)
		}
		PersistBarrier {
			record.done <- true
		}
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
	store := w.store or { return fallback }
	return new_stored_generator(store, fallback)
}

// flush persists this world's store to disk without unloading it, waiting
// for every write already handed to the storage worker before this call to
// actually be applied first. So this reflects everything mutated up to
// the moment it was called.. Safe to call while the world is live. It doesn't
// touch the in memory override cache.
pub fn (mut w World) flush() {
	if mut store := w.store {
		w.await_persist_barrier()
		store.flush()
	}
}

// close waits for the storage worker to apply every write already handed
// to it, then stops it before closing the store.
pub fn (mut w World) close() {
	if mut store := w.store {
		w.persist_stop <- true
		_ := <-w.persist_done
		store.close()
	}
}

// await_persist_barrier blocks until the storage worker has applied every
// record enqueued before this call.
fn (mut w World) await_persist_barrier() {
	if !w.store_backed {
		return
	}
	done := chan bool{cap: 1}
	w.persist_queue <- PersistBarrier{
		done: done
	}
	_ := <-done
}
