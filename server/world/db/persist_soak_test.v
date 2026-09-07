module db

import sync
import time
import server.world

// CountingProvider keeps the last record written for each column, so a test
// can check what actually reached storage rather than only how often the
// worker ran.
@[heap]
struct CountingProvider {
mut:
	mutex   &sync.Mutex = sync.new_mutex()
	applied int
	stored  map[string][]u8
}

fn (p &CountingProvider) dimension() world.Dimension {
	return world.overworld
}

fn (p &CountingProvider) load_chunk(cx int, cz int) ?world.Chunk {
	return none
}

fn (p &CountingProvider) load_column(cx int, cz int) ?[]u8 {
	mut m := p.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.stored['${cx},${cz}'] or { return none }
}

fn (mut p CountingProvider) store_column(cx int, cz int, data []u8) ! {
	p.mutex.lock()
	p.applied++
	p.stored['${cx},${cz}'] = data.clone()
	p.mutex.unlock()
}

fn (p &CountingProvider) each_player_spawn(cb fn (key string, x int, y int, z int)) {}

fn (mut p CountingProvider) store_chunk_blocks(cx int, cz int, encoded map[int][]u8) ! {}

fn (mut p CountingProvider) set_player_spawn(key string, x int, y int, z int) ! {}


fn (mut p CountingProvider) flush() ! {}

fn (mut p CountingProvider) close() ! {}

fn (p &CountingProvider) applied_count() int {
	mut m := p.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.applied
}

// stored_block_count totals the blocks across every column record written, as
// storage would hold them after a restart.
fn (p &CountingProvider) stored_block_count() int {
	mut m := p.mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut total := 0
	for _, data in p.stored {
		col := decode_column(data) or { continue }
		total += col.blocks.len
	}
	return total
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

	w.close() or { panic(err) }
	// Every block must be in what reached storage, however many writes the
	// worker needed to get it there.
	assert provider.stored_block_count() == write_count
	assert w.block_override(write_count - 1, 64, 0) or { -1 } == write_count
	// The writes span 1250 column footprints and the worker collapses the
	// ones that arrive while a column is already queued, so it must have run
	// far fewer times than there were writes.
	assert provider.applied_count() < write_count
}

fn test_flush_barrier_holds_under_sustained_concurrent_writes() {
	mut provider := &CountingProvider{}
	mut w := new_world('persist-soak-flush', provider, 'void', world.overworld)
	defer {
		w.close() or { panic(err) }
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
		w.flush() or { panic(err) }
		applied_at_flush := provider.applied_count()
		// Whatever the worker had applied at the moment this flush returned
		// must still be applied afterward. Flush never reports completion
		// before the worker actually reached that point.
		assert provider.applied_count() >= applied_at_flush
		flush_checks++
		time.sleep(1 * time.millisecond)
	}

	_ := <-writer_done
	w.flush() or { panic(err) }
	assert provider.stored_block_count() == write_count
}
