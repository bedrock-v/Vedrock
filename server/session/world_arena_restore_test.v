module session

import time
import server.internal.gamedata
import server.world
import server.world.db
import server.worldrt

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

fn (t ArenaRestoreBarrierTask) run(mut tx worldrt.WorldTx) {
	t.started <- true
	_ := <-t.release
}

struct ArenaFairnessMarkerTask {
	done chan bool
}

fn (t ArenaFairnessMarkerTask) name() string {
	return 'ArenaFairnessMarkerTask'
}

fn (t ArenaFairnessMarkerTask) run(mut tx worldrt.WorldTx) {
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

struct ArenaQueueFillerTask {}

fn (t ArenaQueueFillerTask) name() string {
	return 'ArenaQueueFillerTask'
}

fn (t ArenaQueueFillerTask) run(mut tx worldrt.WorldTx) {
	time.sleep(time.millisecond)
}

fn test_arena_restore_completes_while_the_world_queue_stays_full() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('arena-restore-saturated', none, 'void', world.overworld)
	hub.add_world(w)
	mut wr := hub.world_runtime('arena-restore-saturated') or { panic('expected runtime') }
	defer {
		hub.close_worlds()
	}

	blocks_needed := arena_restore_batch_size * 4 + 1
	mut src := SequentialBlockSource{}
	snap := world.capture(mut src, world.new_box(0, 64, 0, blocks_needed - 1, 64, 0))!

	// Keep the world queue at capacity for the whole restore. A restore that
	// hands its remaining batches back through the queue never finishes here.
	stop := chan bool{cap: 1}
	feeder_done := chan bool{cap: 1}
	spawn fn [mut wr, stop, feeder_done] () {
		for {
			select {
				_ := <-stop {
					feeder_done <- true
					return
				}
				else {}
			}
			wr.try_submit(ArenaQueueFillerTask{})
		}
	}()

	hub.restore_area(snap)

	restored := arena_restore_wait_until(10000, fn [wr, blocks_needed] () bool {
		id := wr.world.block_override(blocks_needed - 1, 64, 0) or { return false }
		return id == blocks_needed
	})
	stop <- true
	_ := <-feeder_done
	assert restored, 'restore abandoned its remaining batches under a saturated queue'
}
