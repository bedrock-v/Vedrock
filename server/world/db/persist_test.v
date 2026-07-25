module db

import time
import server.world

// RecordingProvider is a test only Provider that records calls in order
// and can block the first set_block until released, proving that world
// mutation and persistence happen on different threads.
@[heap]
struct RecordingProvider {
mut:
	calls   []string
	started chan bool = chan bool{cap: 1}
	release chan bool = chan bool{cap: 1}
	claim   chan bool
}

fn new_recording_provider() &RecordingProvider {
	claim := chan bool{cap: 1}
	claim <- true
	return &RecordingProvider{
		claim: claim
	}
}

fn (p &RecordingProvider) dimension() world.Dimension {
	return world.overworld
}

fn (p &RecordingProvider) load_chunk(cx int, cz int) ?world.Chunk {
	return none
}

fn (p &RecordingProvider) each_block(cb fn (x int, y int, z int, runtime_id int)) {}

fn (p &RecordingProvider) each_tile(cb fn (x int, y int, z int, text string)) {}

fn (mut p RecordingProvider) set_block(x int, y int, z int, runtime_id int) {
	mut claimed := false
	select {
		_ := <-p.claim {
			claimed = true
		}
		else {}
	}
	if claimed {
		select {
			p.started <- true {}
			else {}
		}
		_ := <-p.release
	}
	p.calls << 'set_block'
}

fn (mut p RecordingProvider) set_tile_text(x int, y int, z int, text string) {
	p.calls << 'set_tile_text'
}

fn (mut p RecordingProvider) flush() {
	p.calls << 'flush'
}

fn (mut p RecordingProvider) close() {
	p.calls << 'close'
}

fn persist_wait_until(deadline_ms int, cond fn () bool) bool {
	deadline := time.now().add(deadline_ms * time.millisecond)
	for time.now() < deadline {
		if cond() {
			return true
		}
		time.sleep(2 * time.millisecond)
	}
	return cond()
}

// set_block must return before the actual disk write happens.
fn test_set_block_does_not_wait_for_the_storage_worker() {
	mut provider := new_recording_provider()
	mut w := new_world('persist-test', provider, 'void', world.overworld)
	defer {
		provider.release <- true // let the blocked worker call finish so close() below can too
		w.close()
	}

	w.set_block(1, 64, 1, 42)
	// The in memory side is immediately visible regardless of the disk
	// write's own progress.
	assert w.block_override(1, 64, 1) or { -1 } == 42

	_ := <-provider.started // the worker is now provably blocked on its own thread
	assert provider.calls.len == 0 // the disk write has not landed yet
}

fn test_close_waits_for_pending_storage_writes() {
	mut provider := new_recording_provider()
	mut w := new_world('persist-test-close', provider, 'void', world.overworld)

	w.set_block(1, 64, 1, 42)
	_ := <-provider.started // the worker is blocked mid write

	close_done := chan bool{cap: 1}
	spawn fn [mut w, close_done] () {
		w.close()
		close_done <- true
	}()

	// close() must not have finished yet, the write it should wait for is
	// still blocked. Give it a bounded window it must not (incorrectly)
	// complete within.
	select {
		_ := <-close_done {
			assert false // close() returned while a pending write was still blocked
		}
		200 * time.millisecond {}
	}

	provider.release <- true // let the blocked write finish

	select {
		_ := <-close_done {}
		2000 * time.millisecond {
			assert false // close() should have completed shortly after release
		}
	}

	// The write landed strictly before the provider was closed, never after.
	assert provider.calls == ['set_block', 'close']
}

fn test_flush_waits_for_the_storage_worker() {
	mut provider := new_recording_provider()
	mut w := new_world('persist-test-flush', provider, 'void', world.overworld)
	defer {
		w.close()
	}

	w.set_block(1, 64, 1, 42)
	_ := <-provider.started // the worker is blocked mid write

	flush_done := chan bool{cap: 1}
	spawn fn [mut w, flush_done] () {
		w.flush()
		flush_done <- true
	}()

	select {
		_ := <-flush_done {
			assert false // flush() returned while a pending write was still blocked
		}
		200 * time.millisecond {}
	}

	provider.release <- true

	select {
		_ := <-flush_done {}
		2000 * time.millisecond {
			assert false // flush() should have completed shortly after release
		}
	}

	assert provider.calls == ['set_block', 'flush']
}

// A storeless World never starts a worker and
// must not block on set_block/close at all.
fn test_store_less_world_never_blocks_on_persistence() {
	mut w := new_world('persist-test-void', none, 'void', world.overworld)
	w.set_block(1, 64, 1, 42)
	assert w.block_override(1, 64, 1) or { -1 } == 42
	w.close()
	w.flush()
}
