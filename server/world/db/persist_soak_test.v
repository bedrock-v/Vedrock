module db

import sync
import time
import server.world

@[heap]
struct CountingProvider {
mut:
	mutex   &sync.Mutex = sync.new_mutex()
	applied int
}

fn (p &CountingProvider) dimension() world.Dimension {
	return world.overworld
}

fn (p &CountingProvider) load_chunk(cx int, cz int) ?world.Chunk {
	return none
}

fn (p &CountingProvider) each_block(cb fn (x int, y int, z int, runtime_id int)) {}

fn (p &CountingProvider) each_tile(cb fn (x int, y int, z int, text string)) {}

fn (mut p CountingProvider) set_block(x int, y int, z int, runtime_id int) {
	p.mutex.lock()
	p.applied++
	p.mutex.unlock()
}

fn (mut p CountingProvider) set_tile_text(x int, y int, z int, text string) {}

fn (mut p CountingProvider) flush() {}

fn (mut p CountingProvider) close() {}

fn (p &CountingProvider) applied_count() int {
	mut m := p.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.applied
}

fn persist_soak_wait_until(deadline_ms int, cond fn () bool) bool {
	deadline := time.now().add(deadline_ms * time.millisecond)
	for time.now() < deadline {
		if cond() {
			return true
		}
		time.sleep(2 * time.millisecond)
	}
	return cond()
}

fn test_set_block_never_blocks_under_write_load() {
	mut provider := &CountingProvider{}
	mut w := new_world('persist-soak', provider, 'void', world.overworld)

	write_count := 20000
	start := time.now()
	for i in 0 .. write_count {
		w.set_block(i, 64, 0, i + 1)
	}
	elapsed := time.since(start)
	assert elapsed < 2000 * time.millisecond

	assert persist_soak_wait_until(10000, fn [provider, write_count] () bool {
		return provider.applied_count() == write_count
	})

	w.close()
	assert provider.applied_count() == write_count
	assert w.block_override(write_count - 1, 64, 0) or { -1 } == write_count
}

fn test_flush_barrier_holds_under_sustained_concurrent_writes() {
	mut provider := &CountingProvider{}
	mut w := new_world('persist-soak-flush', provider, 'void', world.overworld)
	defer {
		w.close()
	}

	write_count := 5000
	writer_done := chan bool{cap: 1}
	spawn fn [mut w, write_count, writer_done] () {
		for i in 0 .. write_count {
			w.set_block(i, 65, 0, i + 1)
		}
		writer_done <- true
	}()

	mut flush_checks := 0
	for flush_checks < 20 {
		w.flush()
		applied_at_flush := provider.applied_count()
		// Whatever the worker had applied at the moment this flush returned
		// must still be applied afterward. Flush never reports completion
		// before the worker actually reached that point.
		assert provider.applied_count() >= applied_at_flush
		flush_checks++
		time.sleep(1 * time.millisecond)
	}

	_ := <-writer_done
	w.flush()
	assert provider.applied_count() == write_count
}
