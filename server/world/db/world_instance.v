module db

import sync
import sync.stdatomic
import time
import bedrock_v.nbt
import server.world
import bedrock_v.protocol.types
import server.internal.logger

const persist_shutdown_timeout = 30 * time.second

// persist_high_water_count and persist_hard_ceiling_count define the
// persistence backlog thresholds for a world.
//
// Reaching the high water mark reports persistence pressure but continues
// accepting writes. Reaching the hard ceiling blocks new persistence
// enqueues until the backlog drains. Persistence records are never dropped.
const persist_high_water_count = 4096

const persist_hard_ceiling_count = 32768

// persist_ceiling_poll_interval controls how often a blocked persistence
// enqueue rechecks whether the backlog has fallen below the hard ceiling.
const persist_ceiling_poll_interval = 5 * time.millisecond

// world_resident_column_limit caps how many columns a world keeps in memory.
// A radius 8 view is around 290 columns, so this holds a few players' worth of
// what is actually in play and an evicted column costs one point lookup to
// bring back.
const world_resident_column_limit = 1024

// world_base_chunk_cache_size caps the decoded chunks the storage worker keeps
// to lay column blocks over. A decoded chunk costs hundreds of kilobytes, so
// this is sized to the few columns being written at once, not to how many are
// resident.
const world_base_chunk_cache_size = 8

// ColumnPersist names a column whose changes are already in a World's in
// memory state and not yet on disk. It carries no data of its own: the storage
// worker snapshots the column when it reaches the record, which is what lets
// every write to that column between enqueue and snapshot ride on one disk
// write. PlayerSpawnPersist does carry its write, being one small value.
// PersistBarrier lets a caller learn when the worker has caught up to a
// specific point, for flush/close. A sum type keeps these distinct rather than
// one struct with fields that are only sometimes meaningful.
struct ColumnPersist {
	key i64
}

struct PlayerSpawnPersist {
	key string
	x   int
	y   int
	z   int
}

struct PersistBarrier {
	done chan bool
}

// PersistFlush is a sync queued behind everything already written. The queue is
// ordered, so reaching it means every earlier write has been applied.
// The same guarantee a barrier gives without a caller waiting on it.
struct PersistFlush {}

type PersistRecord = ColumnPersist | PersistBarrier | PersistFlush | PlayerSpawnPersist

// QueuedPersistRecord pairs a persistence record with its enqueue time for
// measuring backlog depth and age.
struct QueuedPersistRecord {
	record      PersistRecord
	enqueued_at time.Time
}

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
	store ?Provider
	// columns is everything this world has written into its terrain, grouped
	// by the chunk footprint it sits in: block overrides and block entities of
	// every kind together. Grouping is what keeps a chunk send from walking
	// the whole world and what gives the storage worker one write unit.
	columns map[i64]&Column
	// column_seq orders columns by last use for eviction, and loaded_columns
	// names the ones that have arrived since a caller last asked.
	column_seq     i64
	loaded_columns []i64
	// pending_migration names columns read back still carrying blocks, waiting
	// for a persist record to be queued outside the lock column() holds.
	pending_migration []i64
	// base_chunks is the terrain the storage worker lays a column's blocks
	// over, kept so a repeatedly edited column is not read back or regenerated
	// on every write. Capped by count, oldest first.
	base_chunks      map[i64]world.Chunk
	base_chunk_order []i64
	// chunk_cache is what the store answered for a column, shared by every
	// generator this world hands out so that one write invalidates it for all
	// of them. It has its own lock and is never held under w.mutex.
	chunk_cache &ChunkCache = &ChunkCache{}
	// generator is this world's own generator, handed over by the runtime that
	// builds it. Resolving the name here would reach only the built in
	// generators, so a world running a registered custom one would have its
	// terrain read, and baked, as something it never was.
	generator ?world.Generator
	// stored is generator wrapped so the store answers first, built once
	// rather than per block query: block_id sits on the tick path.
	stored ?world.Generator
	// player_spawns is the bed each player is bound to here, keyed by whatever
	// the caller identifies a player by. It belongs to the world because the
	// coordinates only mean anything in this one and it goes when the world
	// does.
	player_spawns map[string]types.BlockPosition
	open_holders  map[string]u64
	// furnace_states is the burn and cook progress of every furnace that is
	// doing something. It is in memory only: a furnace goes out across a
	// restart rather than resuming mid-cook.
	furnace_states     map[string]FurnaceState
	mutex &sync.Mutex = sync.new_mutex()
	// store_mutex serialises every call into store. The backends here are not
	// thread safe and columns are now read from whatever thread asked for one
	// while the storage worker is writing on its own. w.mutex may be held
	// while taking this; never the other way round.
	store_mutex        &sync.Mutex = sync.new_mutex()
	current_tick       i64
	scheduled          []ScheduledEntry
	last_persist_error ?string
	// Persistence worker state, only meaningful when store_backed is true.
	// A storeless World (tests, void worlds) never starts this thread and
	// must never touch these fields.
	store_backed    bool
	persist_mutex   &sync.Mutex = sync.new_mutex()
	persist_records []QueuedPersistRecord
	// persist_head points to the first pending persistence record.
	// Records before it have already been applied and are compacted
	// periodically, avoiding repeated front deletions from the queue.
	persist_head   int
	persist_wakeup chan bool = chan bool{cap: 1}
	persist_stop   chan bool = chan bool{cap: 1}
	persist_done   chan bool = chan bool{cap: 1}

	// Monotonic persistence totals used to measure enqueue and commit rates.
	persist_enqueued_count  &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	persist_committed_count &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)

	// Provider write latency and error state metrics.
	// consecutive_errors resets after the next successful write.
	persist_last_write_ns      &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	persist_longest_write_ns   &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	persist_consecutive_errors &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)

	// Resident column ceiling. Tests may override this value.
	resident_column_limit int = world_resident_column_limit

	// Persistence backlog thresholds. Tests may override these values.
	persist_high_water_threshold   int = persist_high_water_count
	persist_hard_ceiling_threshold int = persist_hard_ceiling_count

	// Timeout used while waiting for persistence shutdown to complete.
	persist_shutdown_timeout_value time.Duration = persist_shutdown_timeout

	// closing and closed make close() idempotent. closing prevents duplicate
	// stop signals while shutdown is still in progress; closed is set only
	// after the underlying store closes successfully.
	closing bool
	closed  bool
pub mut:
	generator_name string
	// seed is what this world's generator is built with. 0 is a world made
	// before seeds existed, which keeps generating as it always did.
	seed i64
	// spawn is where a player new to this world arrives, worked out once when
	// it was created. none is a world from before spawns were stored.
	spawn_point ?world.SpawnPoint
}

pub struct BlockOverride {
pub:
	x  int
	y  int
	z  int
	id int
}

// TileEntry is a block entity's text paired with its position, returned by
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

// load pulls this world's player spawns into memory. Columns are not loaded
// here: they arrive as they are touched, see column().
pub fn (mut w World) load() {
	store := w.store or { return }
	w.store_mutex.lock()
	store.each_player_spawn(fn [mut w] (key string, x int, y int, z int) {
		w.player_spawns[key] = types.BlockPosition{x, y, z}
	})
	w.store_mutex.unlock()
}

// The four calls below are every way this file reaches a Provider, each one
// holding store_mutex for the duration. See its comment on World.
fn (mut w World) locked_store_column(mut store Provider, cx int, cz int, data []u8) ! {
	w.store_mutex.lock()
	defer {
		w.store_mutex.unlock()
	}
	store.store_column(cx, cz, data)!
}

fn (mut w World) locked_set_player_spawn(mut store Provider, key string, x int, y int, z int) ! {
	w.store_mutex.lock()
	defer {
		w.store_mutex.unlock()
	}
	store.set_player_spawn(key, x, y, z)!
}

fn (mut w World) locked_store_flush(mut store Provider) ! {
	w.store_mutex.lock()
	defer {
		w.store_mutex.unlock()
	}
	store.flush()!
}

fn (mut w World) locked_store_close(mut store Provider) ! {
	w.store_mutex.lock()
	defer {
		w.store_mutex.unlock()
	}
	store.close()!
}

// column returns a column by key, reading it from the store the first time and
// creating an empty one when the store has nothing there. A column stays
// resident until eviction, so an empty result is remembered too and a position
// nobody has ever written is not a lookup every time it is read.
//
// The store read happens under w.mutex. It is a point lookup and holding the
// lock across it is what keeps residency, eviction and mutation a single
// consistent step rather than a sequence another thread can interleave with.
// Callers hold w.mutex.
fn (mut w World) column(key i64) &Column {
	w.column_seq++
	if mut col := w.columns[key] {
		col.last_used = w.column_seq
		return col
	}
	mut col := &Column{}
	if store := w.store {
		cx, cz := column_coords(key)
		w.store_mutex.lock()
		record := store.load_column(cx, cz) or { []u8{} }
		w.store_mutex.unlock()
		if mut loaded := decode_column(record) {
			col = loaded
			// A record still carrying blocks predates them being written into
			// the chunk data. Marking it dirty is the whole migration: the
			// storage worker bakes it on its next pass and writes the record
			// back without them.
			if col.blocks.len > 0 && !isnil(world.block_palette()) {
				col.dirty = true
				w.pending_migration << key
			}
		}
	}
	col.last_used = w.column_seq
	w.columns[key] = col
	w.loaded_columns << key
	w.evict_columns_locked(key)
	return col
}

// drain_pending_migrations queues a persist record for every column that came
// back still carrying blocks. column() can't enqueue from where it runs.
// The callers that can do it on their way out.
fn (mut w World) drain_pending_migrations() {
	w.mutex.lock()
	keys := w.pending_migration.clone()
	w.pending_migration.clear()
	w.mutex.unlock()
	for key in keys {
		w.enqueue_persist(ColumnPersist{
			key: key
		})
	}
}

// evict_columns_locked drops the least recently used columns once the world
// holds more than resident_column_limit of them. A column with changes
// the storage worker has not taken yet is never evicted, dropping it would
// discard those changes, so the limit is a target rather than a hard ceiling.
// Callers hold w.mutex.
fn (mut w World) evict_columns_locked(keep i64) {
	for w.columns.len > w.resident_column_limit {
		mut oldest := i64(0)
		mut oldest_seq := i64(0)
		mut found := false
		for key, col in w.columns {
			if key == keep || col.dirty {
				continue
			}
			if !found || col.last_used < oldest_seq {
				oldest = key
				oldest_seq = col.last_used
				found = true
			}
		}
		if !found {
			return
		}
		w.columns.delete(oldest)
	}
}

// take_loaded_columns returns the columns that have become resident since the
// last call and clears the list.
pub fn (mut w World) take_loaded_columns() []i64 {
	w.mutex.lock()
	defer {
		w.mutex.unlock()
	}
	out := w.loaded_columns.clone()
	w.loaded_columns.clear()
	return out
}

// mark_column_dirty records a column as changed and reports whether the
// storage worker needs a new record for it. It returns false while a record
// for the column is already queued which is how many writes to one column
// collapse into one disk write. Callers hold w.mutex.
fn mark_column_dirty(mut col Column) bool {
	if col.dirty {
		return false
	}
	col.dirty = true
	return true
}

// player_spawn is the bed the named player is bound to in this world or none
// when they have never used one here. A world only knows its own: the same
// player has an unrelated answer, or none, in every other world.
pub fn (w &World) player_spawn(key string) ?types.BlockPosition {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return w.player_spawns[key] or { return none }
}

pub fn (mut w World) set_player_spawn(key string, pos types.BlockPosition) {
	w.mutex.lock()
	w.player_spawns[key] = pos
	w.mutex.unlock()
	w.enqueue_persist(PlayerSpawnPersist{
		key: key
		x:   pos.x
		y:   pos.y
		z:   pos.z
	})
}

// set_block updates the in memory override immediately, under mutex, then
// hands the actual disk write to the storage worker rather than performing
// it here. Callers see the new value right away regardless of disk speed;
// see the World comment above for exactly what that trades away.
pub fn (mut w World) set_block(x int, y int, z int, runtime_id int) {
	w.mutex.lock()
	key := column_key_of(x, z)
	mut col := w.column(key)
	col.blocks[local_key(x, y, z)] = runtime_id
	queue := mark_column_dirty(mut col)
	w.mutex.unlock()
	if queue {
		w.enqueue_persist(ColumnPersist{
			key: key
		})
	}
}

pub fn (mut w World) block_override(x int, y int, z int) ?int {
	w.mutex.lock()
	defer {
		w.mutex.unlock()
	}
	col := w.column(column_key_of(x, z))
	return col.blocks[local_key(x, y, z)] or { return none }
}

// resident_column_count is how many columns the world is holding in memory.
pub fn (w &World) resident_column_count() int {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return w.columns.len
}

// resident_block_count totals the overrides in the columns currently in
// memory. It is not the world's total: columns load as they are touched.
pub fn (w &World) resident_block_count() int {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut total := 0
	for _, col in w.columns {
		total += col.blocks.len
	}
	return total
}

pub fn (mut w World) overrides_in_chunk(cx int, cz int) []BlockOverride {
	w.mutex.lock()
	defer {
		w.mutex.unlock()
	}
	col := w.column(column_key(cx, cz))
	mut out := []BlockOverride{cap: col.blocks.len}
	for local, id in col.blocks {
		x, y, z := local_coords(cx, cz, local)
		out << BlockOverride{
			x:  x
			y:  y
			z:  z
			id: id
		}
	}
	return out
}

// set_tile_text updates the in memory block entity immediately, under mutex,
// then hands the actual disk write to the storage worker. The same split
// set_block uses, and for the same reason.
pub fn (mut w World) set_tile_text(x int, y int, z int, text string) {
	w.update_block_entity(x, y, z, block_entity_text_key, nbt.Tag(text))
}

// update_block_entity sets one field of the block entity at a position,
// keeping whatever other kinds have put there. Every block entity write goes
// through here which is what makes adding a kind a matter of choosing a key.
fn (mut w World) update_block_entity(x int, y int, z int, key string, value nbt.Tag) {
	w.mutex.lock()
	column := column_key_of(x, z)
	local := local_key(x, y, z)
	mut col := w.column(column)
	mut data := col.block_entities[local] or { nbt.new_compound() }
	data.set(key, value)
	col.block_entities[local] = data
	queue := mark_column_dirty(mut col)
	w.mutex.unlock()
	if queue {
		w.enqueue_persist(ColumnPersist{
			key: column
		})
	}
}

// enqueue_persist queues a persistence record and wakes the storage worker.
// Enqueues remain non blocking until the hard backlog ceiling is reached; at
// the ceiling, callers wait for the queue to drain.
fn (mut w World) enqueue_persist(record PersistRecord) {
	if !w.store_backed {
		return
	}
	for w.pending_persist_count() >= w.persist_hard_ceiling_threshold {
		time.sleep(persist_ceiling_poll_interval)
	}
	w.persist_mutex.lock()
	w.persist_records << QueuedPersistRecord{
		record:      record
		enqueued_at: time.now()
	}
	w.persist_mutex.unlock()
	mut enqueued := w.persist_enqueued_count
	enqueued.add(1)
	select {
		w.persist_wakeup <- true {}
		else {}
	}
}

// run_persist_worker is the storage worker: the only thread that writes to
// store, though no longer the only one that reaches it, since a column is read
// on whatever thread asked for it. store_mutex is what keeps those apart.
// Started once by new_world, only when store is present.
fn (mut w World) run_persist_worker() {
	logger.name_thread('Persist Worker/${w.name}')
	defer {
		logger.unname_thread()
	}
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
// the pending count (persist_head has already advanced past it).
//
// Advancing persist_head is O(1); persist_records itself is only
// compacted once that prefix reaches half the slice.
fn (mut w World) drain_persist_records(mut store Provider) {
	for {
		w.persist_mutex.lock()
		if w.persist_head >= w.persist_records.len {
			w.persist_records = []QueuedPersistRecord{}
			w.persist_head = 0
			w.persist_mutex.unlock()
			return
		}
		queued := w.persist_records[w.persist_head]
		w.persist_head++
		if w.persist_head >= w.persist_records.len / 2 + 1 {
			w.persist_records = w.persist_records[w.persist_head..].clone()
			w.persist_head = 0
		}
		w.persist_mutex.unlock()
		apply_persist_record(mut w, mut store, queued.record)
		mut committed := w.persist_committed_count
		committed.add(1)
	}
}

// apply_persist_record performs the one disk write, or barrier signal, a
// single record represents. A write failure is recorded on World rather than
// discarded.
fn apply_persist_record(mut w World, mut store Provider, record PersistRecord) {
	match record {
		ColumnPersist {
			snapshot := w.snapshot_column(record.key) or { return }
			cx, cz := column_coords(record.key)
			start := time.now()
			mut ok := true
			w.bake_column_blocks(mut store, record.key, snapshot) or {
				w.mutex.lock()
				w.last_persist_error = err.msg()
				w.mutex.unlock()
				ok = false
			}
			if ok {
				w.locked_store_column(mut store, cx, cz, snapshot.record) or {
					w.mutex.lock()
					w.last_persist_error = err.msg()
					w.mutex.unlock()
					ok = false
				}
			}
			w.record_persist_write_result(start, ok)
		}
		PlayerSpawnPersist {
			start := time.now()
			mut ok := true
			w.locked_set_player_spawn(mut store, record.key, record.x, record.y, record.z) or {
				w.mutex.lock()
				w.last_persist_error = err.msg()
				w.mutex.unlock()
				ok = false
			}
			w.record_persist_write_result(start, ok)
		}
		PersistFlush {
			start := time.now()
			mut ok := true
			w.locked_store_flush(mut store) or {
				w.mutex.lock()
				w.last_persist_error = err.msg()
				w.mutex.unlock()
				ok = false
			}
			w.record_persist_write_result(start, ok)
		}
		PersistBarrier {
			record.done <- true
		}
	}
}

// ColumnSnapshot is one column as the storage worker will write it: the blocks
// to bake into the chunk data and the record holding everything the chunk
// format has no place for. blocks is empty when there is no palette to name
// them with and the record then carries them instead.
struct ColumnSnapshot {
	blocks map[i64]int
	record []u8
}

// bake_column_blocks writes a column's blocks into the world's chunk data in
// the game's own format.
fn (mut w World) bake_column_blocks(mut store Provider, key i64, snapshot ColumnSnapshot) ! {
	if snapshot.blocks.len == 0 {
		return
	}
	cx, cz := column_coords(key)
	mut chunk := w.base_chunk(mut store, cx, cz)
	for local, id in snapshot.blocks {
		x, y, z := local_coords(cx, cz, local)
		chunk.set_block_id(x & 15, y, z & 15, id)
	}
	encoded := encode_chunk_sections(chunk, w.dimension)!
	w.store_mutex.lock()
	store.store_chunk_blocks(cx, cz, encoded) or {
		w.store_mutex.unlock()
		return err
	}
	w.store_mutex.unlock()
	// The column on disk has changed, so whatever a reader was told about it
	// before is now the old world.
	mut cache := w.chunk_cache
	cache.invalidate(cx, cz)
}

// base_chunk is the terrain a column's blocks are laid over: what the store
// holds or what the generator makes for ground this world has only ever made
// up. Reading or generating it is the most expensive thing on this path by a
// wide margin and a column being edited is usually about to be edited again,
// so the last few are kept.
//
// A stale one is still correct. A bake applies every block the column holds,
// not just the newest, so an edit can't be lost by starting from a base that
// predates it.
fn (mut w World) base_chunk(mut store Provider, cx int, cz int) world.Chunk {
	key := column_key(cx, cz)
	w.mutex.lock()
	if cached := w.base_chunks[key] {
		w.mutex.unlock()
		return cached
	}
	w.mutex.unlock()

	w.store_mutex.lock()
	found := store.load_chunk(cx, cz)
	w.store_mutex.unlock()
	chunk := found or { w.generate_column_chunk(cx, cz) }

	w.mutex.lock()
	if key !in w.base_chunks {
		w.base_chunks[key] = chunk
		w.base_chunk_order << key

		for w.base_chunk_order.len > world_base_chunk_cache_size {
			oldest := w.base_chunk_order[0]
			w.base_chunk_order.delete(0)
			w.base_chunks.delete(oldest)
		}
	}
	w.mutex.unlock()
	return chunk
}

// generate_column_chunk makes the terrain a column sits on, for a chunk the
// store has never held. Without it a baked block would be written into an
// otherwise empty chunk and the ground around it would be lost.
fn (w &World) generate_column_chunk(cx int, cz int) world.Chunk {
	mut generator := w.fallback_generator()
	return generator.generate(cx, cz)
}

// set_generator hands this world the generator its runtime resolved for it.
// Called once while the runtime is being built before anything can ask.
pub fn (mut w World) set_generator(g world.Generator) {
	wrapped := w.make_generator(g)
	w.mutex.lock()
	w.generator = g
	w.stored = wrapped
	w.mutex.unlock()
}

// fallback_generator is this world's ground with nothing read back from the
// store. A world used without a runtime has never been handed one, so the name
// is resolved instead which reaches the built in generators only.
pub fn (w &World) fallback_generator() world.Generator {
	mut m := w.mutex
	m.lock()
	held := w.generator
	m.unlock()
	return held or { world.new_generator(w.generator_name) }
}

// stored_generator is this world's ground as it stands: what has been written
// to the store and the generator underneath it for ground nothing has touched.
// This is what a reader needs. An edit lives in the chunk data once it has been
// baked and the in memory overrides that carried it are dropped when the
// column is evicted or the world is loaded again.
pub fn (w &World) stored_generator() world.Generator {
	mut m := w.mutex
	m.lock()
	held := w.stored
	m.unlock()
	if g := held {
		return g
	}
	return w.make_generator(w.fallback_generator())
}

// snapshot_column encodes a column and clears its dirty mark under one lock,
// a write arriving after the snapshot queues a fresh record instead of
// being folded into one that has already been taken. The disk write itself
// happens outside the lock.
//
// A column no longer resident yields none rather than an empty record which
// would erase what is on disk. Eviction never takes a dirty column, so this
// should not arise; writing nothing if it ever does is the difference between
// a lost write and a lost column.
fn (mut w World) snapshot_column(key i64) ?ColumnSnapshot {
	w.mutex.lock()
	defer {
		w.mutex.unlock()
	}
	mut col := w.columns[key] or { return none }
	col.dirty = false
	bake := !isnil(world.block_palette())
	mut blocks := map[i64]int{}
	if bake {
		blocks = col.blocks.clone()
	}
	return ColumnSnapshot{
		blocks: blocks
		record: encode_column_record(col, bake)
	}
}

// record_persist_write_result updates provider write latency and error
// metrics after a persistence write. Barrier signals are not recorded.
fn (mut w World) record_persist_write_result(start time.Time, ok bool) {
	dur := time.since(start).nanoseconds()
	mut last := w.persist_last_write_ns
	last.store(dur)
	mut longest := w.persist_longest_write_ns
	if dur > longest.load() {
		longest.store(dur)
	}
	mut errors := w.persist_consecutive_errors
	if ok {
		errors.store(0)
	} else {
		errors.add(1)
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

// pending_persist_count returns the number of persistence records waiting
// for the storage worker. It is safe to call from any thread.
pub fn (w &World) pending_persist_count() int {
	mut m := w.persist_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return w.persist_records.len - w.persist_head
}

// oldest_pending_persist_age returns how long the oldest pending persistence
// record has been waiting. It returns zero when no records are pending.
pub fn (w &World) oldest_pending_persist_age() time.Duration {
	mut m := w.persist_mutex
	m.lock()
	defer {
		m.unlock()
	}
	if w.persist_head >= w.persist_records.len {
		return time.Duration(0)
	}
	return time.since(w.persist_records[w.persist_head].enqueued_at)
}

// persist_high_water_threshold_value and persist_hard_ceiling_threshold_value
// expose the configured overload policy thresholds for metrics/reporting.
pub fn (w &World) persist_high_water_threshold_value() int {
	return w.persist_high_water_threshold
}

pub fn (w &World) persist_hard_ceiling_threshold_value() int {
	return w.persist_hard_ceiling_threshold
}

// persist_pressure_level classifies the current persistence backlog:
// 0 is normal, 1 is at or above the high-water mark and 2 is at or above
// the hard ceiling where new persistence enqueues are subject to backpressure.
pub fn (w &World) persist_pressure_level() int {
	pending := w.pending_persist_count()
	if pending >= w.persist_hard_ceiling_threshold {
		return 2
	}
	if pending >= w.persist_high_water_threshold {
		return 1
	}
	return 0
}

// last_persist_write_duration returns the duration of the most recent
// provider write. Barrier signals are not included.
pub fn (w &World) last_persist_write_duration() time.Duration {
	mut d := w.persist_last_write_ns
	return time.Duration(d.load())
}

pub fn (w &World) longest_persist_write_duration() time.Duration {
	mut d := w.persist_longest_write_ns
	return time.Duration(d.load())
}

// persist_consecutive_errors returns the number of consecutive provider
// write failures since the last successful write.
pub fn (w &World) persist_consecutive_errors() i64 {
	mut c := w.persist_consecutive_errors
	return c.load()
}

// persist_enqueued_total returns the total number of persistence records
// enqueued since this world started including writes and barriers.
pub fn (w &World) persist_enqueued_total() i64 {
	mut c := w.persist_enqueued_count
	return c.load()
}

// persist_committed_total returns the total number of persistence records
// applied since this world started including writes and barriers.
pub fn (w &World) persist_committed_total() i64 {
	mut c := w.persist_committed_count
	return c.load()
}

pub fn (mut w World) tile_text(x int, y int, z int) ?string {
	w.mutex.lock()
	defer {
		w.mutex.unlock()
	}
	col := w.column(column_key_of(x, z))
	data := col.block_entities[local_key(x, y, z)] or { return none }
	return block_entity_text(data)
}

// container_slot_count is a chest's fixed slot count.
pub const container_slot_count = 27

// set_container_items updates a container's in memory
// contents immediately, under mutex, then hands the actual disk write to
// the storage worker.
pub fn (mut w World) set_container_items(x int, y int, z int, items []ContainerSlotItem) {
	w.update_block_entity(x, y, z, block_entity_items_key, items_tag(items))
}

pub fn (mut w World) container_items(x int, y int, z int) []ContainerSlotItem {
	w.mutex.lock()
	defer {
		w.mutex.unlock()
	}
	col := w.column(column_key_of(x, z))
	data := col.block_entities[local_key(x, y, z)] or { return []ContainerSlotItem{} }
	return block_entity_items(data)
}

// container_slots resolves a container's contents into slot-indexed
// ItemStacks, empty ItemStack{} for any slot with nothing stored.
pub fn (mut w World) container_slots(x int, y int, z int) []types.ItemStack {
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

pub fn (mut w World) tile_entries_in_chunk(cx int, cz int) []TileEntry {
	w.mutex.lock()
	defer {
		w.mutex.unlock()
	}
	col := w.column(column_key(cx, cz))
	mut out := []TileEntry{}
	for local, data in col.block_entities {
		text := block_entity_text(data) or { continue }
		x, y, z := local_coords(cx, cz, local)
		out << TileEntry{
			x:    x
			y:    y
			z:    z
			text: text
		}
	}
	return out
}

// make_generator wraps the given fallback with a StoredGenerator when this
// world has a backing store, so saved chunks are served before the fallback.
pub fn (w &World) make_generator(fallback world.Generator) world.Generator {
	store := w.store or { return fallback }
	return new_stored_generator(store, fallback, w.chunk_cache, w.spawn_point)
}

// flush persists this world's store to disk without unloading it, waiting
// for every write already handed to the storage worker before this call to
// actually be applied first. So this reflects everything mutated up to
// the moment it was called.. Safe to call while the world is live. It doesn't
// touch the in memory override cache.
pub fn (mut w World) flush() ! {
	if mut store := w.store {
		w.await_persist_barrier()!
		w.locked_store_flush(mut store)!
	}
}

// request_flush queues a sync and returns. It is the periodic form: the caller
// is a tick loop that must not wait on a device, and the ordering of the queue
// already gives it everything flush() blocks for.
//
// A backlog at the ceiling means the queue is full of writes that have to land
// first, so there is nothing for a sync to make durable that the next interval
// will not cover. Skipping is what keeps this from ever blocking its caller.
pub fn (mut w World) request_flush() {
	if !w.store_backed || w.pending_persist_count() >= w.persist_hard_ceiling_threshold {
		return
	}
	w.enqueue_persist(PersistFlush{})
}

// set_resident_column_limit lowers the eviction ceiling so a test can reach it
// without writing a thousand columns first.
fn (mut w World) set_resident_column_limit(limit int) {
	w.mutex.lock()
	w.resident_column_limit = limit
	w.mutex.unlock()
}

pub fn (mut w World) set_persist_shutdown_timeout(d time.Duration) {
	w.persist_shutdown_timeout_value = d
}

// close waits for all queued persistence work to finish, stops the storage
// worker and then closes the underlying store.
//
// The operation is idempotent. If a previous close attempt timed out, a
// retry waits for the existing shutdown to complete instead of sending a
// second stop signal.
pub fn (mut w World) close() ! {
	w.mutex.lock()
	if w.closed {
		w.mutex.unlock()
		return
	}
	already_closing := w.closing
	w.closing = true
	w.mutex.unlock()

	mut store := w.store or { return }
	if !already_closing {
		w.persist_stop <- true
	}
	select {
		_ := <-w.persist_done {
			w.locked_store_close(mut store)!
			w.mutex.lock()
			w.closed = true
			w.mutex.unlock()
		}
		w.persist_shutdown_timeout_value {
			return error('world "${w.name}": persistence worker did not stop within ${w.persist_shutdown_timeout_value} - a disk write may still be stuck; not closing the store out from under it')
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
		w.persist_shutdown_timeout_value {
			return error('world "${w.name}": persistence worker did not catch up within ${w.persist_shutdown_timeout_value}')
		}
	}
}

// FurnaceState is how far through burning its fuel and cooking its input one
// furnace is. A furnace with nothing to do keeps no state at all.
pub struct FurnaceState {
pub:
	// burn_ticks is what is left of the current piece of fuel, and burn_total
	// what that piece was worth when it was lit. The client draws the flame
	// from the ratio of the two.
	burn_ticks int
	burn_total int
	cook_ticks int
}

// is_idle reports whether a furnace has neither fuel burning nor a cook in
// progress.
pub fn (f FurnaceState) is_idle() bool {
	return f.burn_ticks <= 0 && f.cook_ticks <= 0
}

// furnace_state returns a furnace's progress, all zeroes when it is idle.
pub fn (w &World) furnace_state(x int, y int, z int) FurnaceState {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return w.furnace_states[override_key(x, y, z)] or { FurnaceState{} }
}

// set_furnace_state stores a furnace's progress. A furnace stays listed while
// it has state, even all-zero state: that is how one that has just been given
// something to cook gets its first tick.
pub fn (mut w World) set_furnace_state(x int, y int, z int, state FurnaceState) {
	w.mutex.lock()
	w.furnace_states[override_key(x, y, z)] = state
	w.mutex.unlock()
}

// clear_furnace_state forgets a furnace, so the tick stops visiting it.
pub fn (mut w World) clear_furnace_state(x int, y int, z int) {
	w.mutex.lock()
	w.furnace_states.delete(override_key(x, y, z))
	w.mutex.unlock()
}

// tracks_furnace reports whether a furnace is currently being ticked.
pub fn (w &World) tracks_furnace(x int, y int, z int) bool {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return override_key(x, y, z) in w.furnace_states
}

// column_positions_of lists the positions in one column holding any of the
// given block ids. It exists so a caller can ask where a column's furnaces are
// without this package having to know what a furnace is.
pub fn (w &World) column_positions_of(key i64, ids []int) []TickPosition {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	col := w.columns[key] or { return []TickPosition{} }
	cx, cz := column_coords(key)
	mut out := []TickPosition{}
	for local, id in col.blocks {
		if id !in ids {
			continue
		}
		x, y, z := local_coords(cx, cz, local)
		out << TickPosition{
			x: x
			y: y
			z: z
		}
	}
	return out
}

// position_from_key reads back the coordinates an override key was built from.
fn position_from_key(key string) ?TickPosition {
	parts := key.split(':')
	if parts.len != 3 {
		return none
	}
	return TickPosition{
		x: parts[0].int()
		y: parts[1].int()
		z: parts[2].int()
	}
}

// burning_furnaces lists the positions with progress to advance, so the tick
// only visits furnaces that are actually doing something.
pub fn (w &World) burning_furnaces() []TickPosition {
	mut m := w.mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut out := []TickPosition{cap: w.furnace_states.len}
	for key, _ in w.furnace_states {
		pos := position_from_key(key) or { continue }
		out << pos
	}
	return out
}
