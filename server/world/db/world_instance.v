module db

import sync
import time
import server.world
import protocol.types

const persist_shutdown_timeout = 30 * time.second

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

struct ContainerPersist {
	x     int
	y     int
	z     int
	items []ContainerSlotItem
}

struct PersistBarrier {
	done chan bool
}

type PersistRecord = BlockPersist | ContainerPersist | PersistBarrier | TilePersist

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
	store          ?Provider
	overrides      map[string]int
	tile_data      map[string]TileData
	container_data map[string][]ContainerSlotItem
	open_holders       map[string]u64
	mutex              &sync.Mutex = sync.new_mutex()
	current_tick       i64
	scheduled          []ScheduledEntry
	last_persist_error ?string
	// Persistence worker state, only meaningful when store_backed is true.
	// A storeless World (tests, void worlds) never starts this thread and
	// must never touch these fields.
	store_backed    bool
	persist_mutex   &sync.Mutex = sync.new_mutex()
	persist_records []PersistRecord
	persist_wakeup  chan bool = chan bool{cap: 1}
	persist_stop    chan bool = chan bool{cap: 1}
	persist_done    chan bool = chan bool{cap: 1}
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

// is_persistent reports whether the world is backed by on disk storage.
// Ephemeral in memory worlds have nothing to load or save, so external
// persistence tied to the world should only run when this returns true.
pub fn (w &World) is_persistent() bool {
	return w.store_backed
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
	store.each_container(fn [mut w] (x int, y int, z int, items []ContainerSlotItem) {
		w.container_data[override_key(x, y, z)] = items
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

// enqueue_persist appends an immutable record to the unbounded persist
// queue and pings the worker. This never blocks, regardless of how far
// behind the storage worker has fallen.
fn (mut w World) enqueue_persist(record PersistRecord) {
	if !w.store_backed {
		return
	}
	w.persist_mutex.lock()
	w.persist_records << record
	w.persist_mutex.unlock()
	select {
		w.persist_wakeup <- true {}
		else {}
	}
}

// run_persist_worker is the storage worker: the only thread that ever calls
// store.set_block/set_tile_text, so those calls need no lock of their own
// beyond store's own internals. Started once by new_world, only when store
// is present.
fn (mut w World) run_persist_worker() {
	mut store := w.store or { return }
	// Catch up on anything enqueued before this thread's first select
	w.drain_persist_records(mut store)
	for {
		select {
			_ := <-w.persist_wakeup {
				w.drain_persist_records(mut store)
			}
			_ := <-w.persist_stop {
				// shutdown only signals stop after nothing more will be
				// enqueued (see World's own close()), so one final drain
				// is exhaustive.
				w.drain_persist_records(mut store)
				w.persist_done <- true
				return
			}
		}
	}
}

// drain_persist_records applies every record currently queued, one at a
// time, until the queue is empty. A record removed here while still inside
// apply_persist_record (a slow or stuck disk write) is already gone from
// persist_records.
fn (mut w World) drain_persist_records(mut store Provider) {
	for {
		w.persist_mutex.lock()
		if w.persist_records.len == 0 {
			w.persist_mutex.unlock()
			return
		}
		record := w.persist_records[0]
		w.persist_records.delete(0)
		w.persist_mutex.unlock()
		apply_persist_record(mut w, mut store, record)
	}
}

// apply_persist_record performs the one disk write, or barrier signal, a
// single record represents. A write failure is recorded on World rather than
// discarded.
fn apply_persist_record(mut w World, mut store Provider, record PersistRecord) {
	match record {
		BlockPersist {
			store.set_block(record.x, record.y, record.z, record.id) or {
				w.mutex.lock()
				w.last_persist_error = err.msg()
				w.mutex.unlock()
			}
		}
		TilePersist {
			store.set_tile_text(record.x, record.y, record.z, record.text) or {
				w.mutex.lock()
				w.last_persist_error = err.msg()
				w.mutex.unlock()
			}
		}
		ContainerPersist {
			store.set_container_items(record.x, record.y, record.z, record.items) or {
				w.mutex.lock()
				w.last_persist_error = err.msg()
				w.mutex.unlock()
			}
		}
		PersistBarrier {
			record.done <- true
		}
	}
}

pub fn (w &World) last_persist_error() ?string {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return w.last_persist_error
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

// container_slot_count is a chest's fixed slot count.
pub const container_slot_count = 27

// set_container_items updates a container's in memory
// contents immediately, under mutex, then hands the actual disk write to
// the storage worker.
pub fn (mut w World) set_container_items(x int, y int, z int, items []ContainerSlotItem) {
	w.mutex.lock()
	w.container_data[override_key(x, y, z)] = items.clone()
	w.mutex.unlock()
	w.enqueue_persist(ContainerPersist{
		x:     x
		y:     y
		z:     z
		items: items
	})
}

pub fn (w &World) container_items(x int, y int, z int) []ContainerSlotItem {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return w.container_data[override_key(x, y, z)] or { return []ContainerSlotItem{} }.clone()
}

// container_slots resolves a container's contents into slot-indexed
// ItemStacks, empty ItemStack{} for any slot with nothing stored.
pub fn (w &World) container_slots(x int, y int, z int) []types.ItemStack {
	mut out := []types.ItemStack{len: container_slot_count}
	for item in w.container_items(x, y, z) {
		if item.slot >= 0 && item.slot < container_slot_count && item.count > 0 {
			out[item.slot] = types.ItemStack{
				id:               item.id
				meta:             item.meta
				count:            item.count
				block_runtime_id: item.block_runtime_id
				raw_extra_data:   item.raw_extra_data.clone()
			}
		}
	}
	return out
}

pub fn (mut w World) set_container_slot(x int, y int, z int, slot int, stack types.ItemStack) {
	mut items := w.container_items(x, y, z).filter(it.slot != slot)
	if stack.count > 0 && stack.id != 0 {
		items << ContainerSlotItem{
			slot:             slot
			id:               stack.id
			meta:             stack.meta
			count:            stack.count
			block_runtime_id: stack.block_runtime_id
			raw_extra_data:   stack.raw_extra_data.clone()
		}
	}
	w.set_container_items(x, y, z, items)
}

// clear_container empties a container's contents (e.g. after its block is
// broken and its items have already been dropped into the world).
pub fn (mut w World) clear_container(x int, y int, z int) {
	w.set_container_items(x, y, z, []ContainerSlotItem{})
}

// try_hold_container claims a container position for one session at a time.
pub fn (mut w World) try_hold_container(x int, y int, z int, runtime_id u64) bool {
	w.mutex.lock()
	defer {
		w.mutex.unlock()
	}
	key := override_key(x, y, z)
	if held_by := w.open_holders[key] {
		if held_by != runtime_id {
			return false
		}
	}
	w.open_holders[key] = runtime_id
	return true
}

pub fn (mut w World) release_container_hold(x int, y int, z int, runtime_id u64) {
	w.mutex.lock()
	defer {
		w.mutex.unlock()
	}
	key := override_key(x, y, z)
	if held_by := w.open_holders[key] {
		if held_by == runtime_id {
			w.open_holders.delete(key)
		}
	}
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
pub fn (mut w World) flush() ! {
	if mut store := w.store {
		w.await_persist_barrier()!
		store.flush()!
	}
}

// close waits for the storage worker to apply every write already handed to
// it, then stops it before closing the store.
pub fn (mut w World) close() ! {
	if mut store := w.store {
		w.persist_stop <- true
		select {
			_ := <-w.persist_done {
				store.close()!
			}
			persist_shutdown_timeout {
				return error('world "${w.name}": persistence worker did not stop within ${persist_shutdown_timeout} - a disk write may still be stuck; not closing the store out from under it')
			}
		}
	}
}

// await_persist_barrier blocks until the storage worker has applied every
// record enqueued before this call or until persist_shutdown_timeout
// elapses. Enqueueing the barrier through the same append+wakeup path as
// any other record keeps it correctly ordered behind whatever was already
// queued, whether that's nothing or a large backlog.
fn (mut w World) await_persist_barrier() ! {
	if !w.store_backed {
		return
	}
	done := chan bool{cap: 1}
	w.enqueue_persist(PersistBarrier{
		done: done
	})
	select {
		_ := <-done {}
		persist_shutdown_timeout {
			return error('world "${w.name}": persistence worker did not catch up within ${persist_shutdown_timeout}')
		}
	}
}
