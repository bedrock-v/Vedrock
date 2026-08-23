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

// Cache limit in bytes. Chunk size varies a lot (empty
// void column vs fully terrainfilled), so a flat entry count limit
// wouldn't actually bound memory.
const chunk_service_cache_budget_bytes = i64(128) * 1024 * 1024

// ChunkResult is what request() delivers: a chunk or cancelled if the
// service shut down before generation ran.
//
// serialized/section_count are the chunk's wire format bytes, computed
// once at generation time.
pub struct ChunkResult {
pub:
	chunk         world.Chunk
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

// One cached chunk plus its precomputed size (bytes) and last used clock
// value, used for LRU eviction.
struct ChunkCacheEntry {
	chunk         world.Chunk
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
	inflight     map[u64]&ChunkRequest
	jobs         chan ChunkGenJob = chan ChunkGenJob{cap: chunk_gen_queue_capacity}
	stop         chan bool        = chan bool{cap: chunk_gen_worker_count}

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
			chunk:         entry.chunk.clone()
			serialized:    entry.serialized.clone()
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

// complete caches the generated chunk and delivers it to every waiter.
// Each waiter gets its own clone. Chunk's slices alias their backing
// arrays on a plain copy, so handing out the shared value would let one
// session's block overrides corrupt another session's view and the
// cache.
fn (mut svc WorldChunkService) complete(key u64, chunk world.Chunk) {
	// Serialize once here instead of once per waiter
	serialized := chunk.serialize()
	section_count := chunk.section_count()

	svc.mutex.lock()
	bytes := chunk.estimated_bytes() + i64(serialized.len)
	svc.evict_until_room_locked(bytes)
	svc.cache_seq++
	svc.cache[key] = ChunkCacheEntry{
		chunk:         chunk
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
				chunk:         chunk.clone()
				serialized:    serialized.clone()
				section_count: section_count
			} {}
			else {}
		}
	}
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
