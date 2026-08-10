module session

import time
import server.internal.gamedata
import server.world
import server.world.db

struct SequentialBlockSource {}

fn (mut s SequentialBlockSource) get_block(x int, y int, z int) int {
	return x + 1
}

struct ArenaRestoreBarrierTask {
	started chan bool
	release chan bool
}

fn (t ArenaRestoreBarrierTask) name() string {
	return 'ArenaRestoreBarrierTask'
}

fn (t ArenaRestoreBarrierTask) run(mut tx WorldTx) {
	t.started <- true
	_ := <-t.release
}

struct ArenaFairnessMarkerTask {
	done chan bool
}

fn (t ArenaFairnessMarkerTask) name() string {
	return 'ArenaFairnessMarkerTask'
}

fn (t ArenaFairnessMarkerTask) run(mut tx WorldTx) {
	t.done <- true
}

fn arena_restore_wait_until(deadline_ms int, cond fn () bool) bool {
	deadline := time.now().add(deadline_ms * time.millisecond)
	for time.now() < deadline {
		if cond() {
			return true
		}
		time.sleep(2 * time.millisecond)
	}
	return cond()
}

fn test_arena_restore_applies_every_block_across_several_batches() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('arena-restore-correctness', none, 'void', world.overworld)
	hub.add_world(w)
	mut wr := hub.world_runtime('arena-restore-correctness') or { panic('expected runtime') }
	defer {
		hub.close_worlds()
	}

	blocks_needed := arena_restore_batch_size * 2 + 1
	mut src := SequentialBlockSource{}
	snap := world.capture(mut src, world.new_box(0, 64, 0, blocks_needed - 1, 64, 0))!
	assert snap.len() == blocks_needed

	hub.restore_area(snap)

	assert arena_restore_wait_until(5000, fn [wr, blocks_needed] () bool {
		id := wr.world.block_override(blocks_needed - 1, 64, 0) or { return false }
		return id == blocks_needed
	})
	assert wr.world.block_override(0, 64, 0) or { -1 } == 1
	assert wr.world.block_override(blocks_needed / 2, 64, 0) or { -1 } == blocks_needed / 2 + 1
	assert wr.world.block_override(blocks_needed - 1, 64, 0) or { -1 } == blocks_needed
}

fn test_arena_restore_yields_between_batches() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('arena-restore-fairness', none, 'void', world.overworld)
	hub.add_world(w)
	mut wr := hub.world_runtime('arena-restore-fairness') or { panic('expected runtime') }
	defer {
		hub.close_worlds()
	}

	blocks_needed := arena_restore_batch_size * 2 + 1
	mut src := SequentialBlockSource{}
	snap := world.capture(mut src, world.new_box(0, 64, 0, blocks_needed - 1, 64, 0))!

	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	assert wr.submit(ArenaRestoreBarrierTask{
		started: started
		release: release
	})
	_ := <-started // actor now provably blocked, before the restore is even queued

	hub.restore_area(snap) // enqueues the restore's first batch behind the barrier

	marker_done := chan bool{cap: 1}
	assert wr.submit(ArenaFairnessMarkerTask{
		done: marker_done
	}) // enqueued behind the restore's first batch

	release <- true

	select {
		_ := <-marker_done {}
		2000 * time.millisecond {
			assert false // marker starved behind the whole restore, not just its first batch
		}
	}

	// The last block only gets written in the restore's final batch, so if
	// the marker really ran between batches rather than after everything,
	// it is not written yet at this exact moment.
	last_id := wr.world.block_override(blocks_needed - 1, 64, 0) or { -1 }
	assert last_id != blocks_needed

	assert arena_restore_wait_until(5000, fn [wr, blocks_needed] () bool {
		id := wr.world.block_override(blocks_needed - 1, 64, 0) or { return false }
		return id == blocks_needed
	})
}
