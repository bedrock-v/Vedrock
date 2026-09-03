module session

import bedrock_v.protocol.types
import server.internal.gamedata
import server.internal.logger
import server.player
import server.world
import server.world.db
import time
import server.worldrt

// SlowFillerTask blocks a world's runtime on its gate.
struct SlowFillerTask {
	gate chan bool
}

fn (t SlowFillerTask) name() string {
	return 'SlowFillerTask'
}

fn (t SlowFillerTask) run(mut tx worldrt.WorldTx) {
	_ := <-t.gate
}

// FastFillerTask is a no-op worldrt.WorldTask used purely to occupy queue capacity.
struct FastFillerTask {
	id int
}

fn (t FastFillerTask) name() string {
	return 'FastFillerTask'
}

fn (t FastFillerTask) run(mut tx worldrt.WorldTx) {}

fn movement_test_session(mut hub Hub, mut wr worldrt.WorldRuntime) &NetworkSession {
	mut s := &NetworkSession{
		player:        player.new_player()
		hub:           hub
		runtime_id:    hub.allocate_runtime_id()
		spawned:       true
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}
	hub.add(s)
	worldrt.world_call[bool]('test', mut wr, fn [s] (mut tx worldrt.WorldTx) bool {
		register_player(mut tx, s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn test_movement_coalesces_rapid_updates_into_one_job() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut s := movement_test_session(mut hub, mut wr)

	gate := chan bool{cap: 1}
	wr.submit(SlowFillerTask{ gate: gate })
	deadline0 := time.now().add(5 * time.second)
	for time.now() < deadline0 && wr.metrics().queued_tasks > 0 {
		time.sleep(1 * time.millisecond)
	}

	// Small steps: the point is that only the last one lands, not that a
	// player can cross twenty blocks in a tick.
	for i in 0 .. 20 {
		s.update_movement(types.Vector3{0.0, f32(i) * 0.1, 0.0}, 0.0, 0.0, 0.0, false)
	}
	assert wr.metrics().queued_tasks == 1

	gate <- true

	deadline := time.now().add(5 * time.second)
	for time.now() < deadline && s.player.position().y != f32(19) * 0.1 {
		time.sleep(5 * time.millisecond)
	}
	assert s.player.position().y == f32(19) * 0.1
}

fn test_movement_try_submit_failure_does_not_strand_pending_snapshot() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut s := movement_test_session(mut hub, mut wr)

	gate := chan bool{cap: 1}
	wr.submit(SlowFillerTask{ gate: gate })

	// Saturate the queue behind the blocked actor so the next try_submit
	// genuinely fails, not just races a fast drain.
	mut filled := 0
	mut ok := true
	for ok {
		ok = wr.try_submit(FastFillerTask{ id: filled })
		if !ok {
			break
		}
		filled++
		if filled > 300 {
			panic('queue did not saturate - worldrt.WorldRuntime.jobs cap may have changed')
		}
	}

	s.update_movement(types.Vector3{1.0, 2.0, 3.0}, 0.0, 0.0, 0.0, false)
	// try_submit failed (queue full): must not report a job as scheduled
	// when none was actually queued.
	assert s.movement_scheduled == false
	pending := s.pending_movement or {
		panic('expected a pending snapshot to survive the failed submit')
	}

	assert pending.position == types.Vector3{1.0, 2.0, 3.0}

	gate <- true
	deadline := time.now().add(5 * time.second)
	for time.now() < deadline && wr.metrics().queued_tasks > 0 {
		time.sleep(5 * time.millisecond)
	}

	// A later packet (the retry mechanism, per design) picks the snapshot
	// back up now that the queue has room.
	want := types.Vector3{0.4, 0.6, 0.8}
	s.update_movement(want, 0.0, 0.0, 0.0, false)
	deadline2 := time.now().add(5 * time.second)
	for time.now() < deadline2 && s.player.position() != want {
		time.sleep(5 * time.millisecond)
	}
	assert s.player.position() == want
}

fn test_movement_before_spawn_is_dropped_not_stranded() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut s := &NetworkSession{
		player:        player.new_player()
		hub:           hub
		runtime_id:    1
		spawned:       false
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}

	s.update_movement(types.Vector3{9.0, 9.0, 9.0}, 0.0, 0.0, 0.0, false)
	assert s.movement_scheduled == false
	assert s.pending_movement == none
	assert wr.metrics().queued_tasks == 0

	s.spawned = true
	hub.add(s)
	worldrt.world_call[bool]('test', mut wr, fn [s] (mut tx worldrt.WorldTx) bool {
		register_player(mut tx, s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	want := types.Vector3{1.0, 1.5, 2.0}
	s.update_movement(want, 0.0, 0.0, 0.0, false)
	deadline := time.now().add(5 * time.second)
	for time.now() < deadline && s.player.position() != want {
		time.sleep(5 * time.millisecond)
	}
	assert s.player.position() == want
}

fn test_movement_scheduling_survives_actor_draining_at_full_speed() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut s := movement_test_session(mut hub, mut wr)

	// Steps a player could actually take: the point of the test is that the
	// last report always lands, however fast the actor drains.
	mut last := types.Vector3{}
	for i in 0 .. 500 {
		last = types.Vector3{f32(i) * 0.001, 0.0, 0.0}
		s.update_movement(last, 0.0, 0.0, 0.0, false)
	}

	deadline := time.now().add(5 * time.second)
	for time.now() < deadline && (s.player.position() != last || s.movement_scheduled) {
		time.sleep(1 * time.millisecond)
	}
	assert s.player.position() == last
	assert s.movement_scheduled == false

	final := types.Vector3{1.0, 0.0, 0.0}
	s.update_movement(final, 0.0, 0.0, 0.0, false)
	deadline2 := time.now().add(5 * time.second)
	for time.now() < deadline2 && s.player.position() != final {
		time.sleep(1 * time.millisecond)
	}
	assert s.player.position() == final
}
