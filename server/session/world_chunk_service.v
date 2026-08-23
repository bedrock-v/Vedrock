module session

import sync
import sync.stdatomic
import time
import server.world
import server.internal.logger

// Max chunks generated at once per world, no matter how many sessions ask.
const chunk_gen_worker_count = 4

// Requests waiting for a free worker before request() blocks the caller.
const chunk_gen_queue_capacity = 256

// Cache limit in bytes, counting the wire bytes the cache actually holds.
// Chunk size varies a lot (empty void column vs fully terrainfilled), so a flat
// entry count limit wouldn't actually bound memory. A radius 8 view is 200-odd
// columns at ~10kB each, so this holds a couple of players' worth of view and
// a miss only costs one regeneration.
const chunk_service_cache_budget_bytes = i64(4) * 1024 * 1024

// Decoded columns kept for block queries and override rebuilds. A decoded
// column costs an order of magnitude more than its wire form, so only the few
// a player is actually interacting with are worth keeping - block queries are
// spatially local, and everything else reads the wire bytes.
const chunk_decoded_cache_size = 24

// ChunkResult is what request() delivers: a column's wire bytes, or cancelled
// if the service shut down before generation ran.
//
// serialized is computed once at generation time and never mutated afterwards,
// so every waiter and every later cache hit shares the one array. Callers hand
// it straight to a LevelChunkPacket; nothing writes through it.
pub struct ChunkResult {
pub:
	serialized    []u8
	section_count int
	cancelled     bool
}

// One in flight (cx, cz) generation. Only touched by request()/complete()/
// shutdown() always under mutex.
struct ChunkRequest {
mut:
	waiters    []chan ChunkResult
	created_at time.Time
}

struct ChunkGenJob {
	key u64
	cx  int
	cz  int
}

// One cached column's wire bytes plus its size and last used clock value, used
// for LRU eviction.
struct ChunkCacheEntry {
	serialized    []u8
	section_count int
	bytes         i64
mut:
	last_used i64
}

// WorldChunkService is one world's chunk generation authority. Sessions
// call request() instead of generating chunks themselves, so N requests
// for the same column collapse into one generation and total concurrent
// generation work stays capped at chunk_gen_worker_count.
//
// Not routed through the world actor: request() runs on session threads
// directly. Sending generation through wr.jobs would stall the whole
// world's actor on chunk work which defeats the point.
@[heap]
pub struct WorldChunkService {
mut:
	generator world.Generator
	mutex     &sync.Mutex = sync.new_mutex()
	closed    bool
	cache     map[u64]ChunkCacheEntry
	// cache_bytes: running total of every entry's bytes. cache_seq: bumped
	// on every hit/insert, so the entry with the smallest last_used is
	// always the least recently used.
	cache_bytes i64
	cache_seq   i64
	// Defaults to chunk_service_cache_budget_bytes; overridable in tests so
	// eviction can be exercised without allocating hundreds of MB.
	budget_bytes i64 = chunk_service_cache_budget_bytes
	// Decoded columns for block queries and override rebuilds, capped by count
	// rather than bytes: there are only ever chunk_decoded_cache_size of them.
	decoded       map[u64]world.Chunk
	decoded_order []u64
	inflight      map[u64]&ChunkRequest
	jobs          chan ChunkGenJob = chan ChunkGenJob{cap: chunk_gen_queue_capacity}
	stop          chan bool        = chan bool{cap: chunk_gen_worker_count}

	published_active_workers &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_queue_depth    &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_requests_total &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	published_dedup_hits     &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
}

pub fn new_chunk_service(generator world.Generator) &WorldChunkService {
	return new_chunk_service_with_budget(generator, chunk_service_cache_budget_bytes)
}

fn new_chunk_service_with_budget(generator world.Generator, budget_bytes i64) &WorldChunkService {
	mut svc := &WorldChunkService{
		generator:    generator
		budget_bytes: budget_bytes
	}
	for _ in 0 .. chunk_gen_worker_count {
		spawn svc.run_worker()
	}
	return svc
}

// request returns a channel that resolves to (cx, cz)'s chunk: instantly
// if cached, attached to an already running generation if one exists or
// queued as a new one. Never blocks the caller beyond a full job queue.
// Safe to call from any thread.
pub fn (mut svc WorldChunkService) request(cx int, cz int) chan ChunkResult {
	key := chunk_cache_key(cx, cz)
	result := chan ChunkResult{cap: 1}

	svc.mutex.lock()
	if svc.closed {
		svc.mutex.unlock()
		result <- ChunkResult{
			cancelled: true
		}
		return result
	}
	if entry := svc.cache[key] {
		svc.cache_seq++
		mut touched := entry
		touched.last_used = svc.cache_seq
		svc.cache[key] = touched
		svc.mutex.unlock()
		result <- ChunkResult{
			serialized:    entry.serialized
			section_count: entry.section_count
		}
		return result
	}
	mut total := svc.published_requests_total
	total.add(1)
	if mut existing := svc.inflight[key] {
		existing.waiters << result
		mut hits := svc.published_dedup_hits
		hits.add(1)
		svc.mutex.unlock()
		return result
	}
	svc.inflight[key] = &ChunkRequest{
		waiters:    [result]
		created_at: time.now()
	}
	svc.mutex.unlock()

	mut depth := svc.published_queue_depth
	depth.add(1)
	svc.jobs <- ChunkGenJob{
		key: key
		cx:  cx
		cz:  cz
	}
	return result
}

fn (mut svc WorldChunkService) run_worker() {
	logger.name_thread('Chunk Worker')
	defer {
		logger.unname_thread()
	}
	mut active := svc.published_active_workers
	mut depth := svc.published_queue_depth
	for {
		select {
			job := <-svc.jobs {
				depth.sub(1)
				active.add(1)
				chunk := svc.generator.generate(job.cx, job.cz)
				active.sub(1)
				svc.complete(job.key, chunk)
			}
			_ := <-svc.stop {
				return
			}
		}
	}
}

// complete caches the generated column's wire bytes and delivers them to every
// waiter. The decoded chunk is not cached: it costs an order of magnitude more
// than its wire form and only the block query and override paths ever need one,
// so those go through decoded() and its much smaller cache instead.
fn (mut svc WorldChunkService) complete(key u64, chunk world.Chunk) {
	// Serialize once here instead of once per waiter
	serialized := chunk.serialize()
	section_count := chunk.section_count()

	svc.mutex.lock()
	bytes := i64(serialized.len)
	svc.evict_until_room_locked(bytes)
	svc.cache_seq++
	svc.cache[key] = ChunkCacheEntry{
		serialized:    serialized
		section_count: section_count
		bytes:         bytes
		last_used:     svc.cache_seq
	}
	svc.cache_bytes += bytes
	req := svc.inflight[key] or {
		svc.mutex.unlock()
		return
	}
	svc.inflight.delete(key)
	waiters := req.waiters.clone()
	svc.mutex.unlock()

	for w in waiters {
		mut ch := w
		select {
			ch <- ChunkResult{
				serialized:    serialized
				section_count: section_count
			} {}
			else {}
		}
	}
}

// decoded_column returns the decoded form of (cx, cz), generating it on a miss.
// The returned chunk is the service's own - callers that mutate it must clone
// first, which is what decoded_clone is for.
fn (mut svc WorldChunkService) decoded_column(cx int, cz int) ?world.Chunk {
	key := chunk_cache_key(cx, cz)
	svc.mutex.lock()
	if svc.closed {
		svc.mutex.unlock()
		return none
	}
	if chunk := svc.decoded[key] {
		svc.mutex.unlock()
		return chunk
	}
	mut generator := svc.generator
	svc.mutex.unlock()

	// Generated outside the lock: a concurrent caller may generate the same
	// column, which wastes one generation but never yields a different column.
	chunk := generator.generate(cx, cz)

	svc.mutex.lock()
	if svc.closed {
		svc.mutex.unlock()
		return chunk
	}
	if existing := svc.decoded[key] {
		svc.mutex.unlock()
		return existing
	}
	svc.decoded[key] = chunk
	svc.decoded_order << key
	for svc.decoded_order.len > chunk_decoded_cache_size {
		svc.decoded.delete(svc.decoded_order[0])
		svc.decoded_order.delete(0)
	}
	svc.mutex.unlock()
	return chunk
}

// decoded_clone returns a private copy of (cx, cz)'s decoded column, for
// callers that apply overrides or otherwise write to it.
pub fn (mut svc WorldChunkService) decoded_clone(cx int, cz int) ?world.Chunk {
	chunk := svc.decoded_column(cx, cz)?
	return chunk.clone()
}

// block_at reads one generated block without copying the column. Block queries
// run per placement and per physics check, so the read has to stay allocation
// free.
pub fn (mut svc WorldChunkService) block_at(x int, y int, z int) int {
	chunk := svc.decoded_column(x >> 4, z >> 4) or { return world.air.network_id }
	return chunk.block_id(x & 15, y, z & 15)
}

fn (mut svc WorldChunkService) evict_until_room_locked(incoming_bytes i64) {
	for svc.cache.len > 0 && svc.cache_bytes + incoming_bytes > svc.budget_bytes {
		mut oldest_key := u64(0)
		mut oldest_seq := i64(0)
		mut found := false
		for k, entry in svc.cache {
			if !found || entry.last_used < oldest_seq {
				oldest_key = k
				oldest_seq = entry.last_used
				found = true
			}
		}
		if !found {
			break
		}
		evicted := svc.cache[oldest_key] or { break }
		svc.cache.delete(oldest_key)
		svc.cache_bytes -= evicted.bytes
	}
}

// shutdown stops every worker and cancels any waiter still stuck on an
// in flight request then refuses further requests.
pub fn (mut svc WorldChunkService) shutdown() {
	svc.mutex.lock()
	svc.closed = true
	for _, req in svc.inflight {
		for w in req.waiters {
			mut ch := w
			select {
				ch <- ChunkResult{
					cancelled: true
				} {}
				else {}
			}
		}
	}
	svc.inflight = map[u64]&ChunkRequest{}
	svc.decoded = map[u64]world.Chunk{}
	svc.decoded_order = []u64{}
	svc.mutex.unlock()
	for _ in 0 .. chunk_gen_worker_count {
		svc.stop <- true
	}
}

// A snapshot of one world's chunk generation health.
pub struct ChunkServiceMetrics {
pub:
	cached_chunks         int
	cached_bytes_estimate i64
	cache_budget_bytes    i64
	inflight_requests     int
	oldest_inflight_age   time.Duration
	active_workers        i64
	worker_limit          int
	queue_depth           i64
	requests_total        i64
	dedup_hits_total      i64
}

pub fn (mut svc WorldChunkService) metrics() ChunkServiceMetrics {
	svc.mutex.lock()
	cached := svc.cache.len
	cached_bytes := svc.cache_bytes
	inflight := svc.inflight.len
	mut oldest := time.Duration(0)
	for _, req in svc.inflight {
		age := time.since(req.created_at)
		if age > oldest {
			oldest = age
		}
	}
	svc.mutex.unlock()

	mut active := svc.published_active_workers
	mut depth := svc.published_queue_depth
	mut total := svc.published_requests_total
	mut hits := svc.published_dedup_hits
	return ChunkServiceMetrics{
		cached_chunks:         cached
		cached_bytes_estimate: cached_bytes
		cache_budget_bytes:    svc.budget_bytes
		inflight_requests:     inflight
		oldest_inflight_age:   oldest
		active_workers:        active.load()
		worker_limit:          chunk_gen_worker_count
		queue_depth:           depth.load()
		requests_total:        total.load()
		dedup_hits_total:      hits.load()
	}
}
