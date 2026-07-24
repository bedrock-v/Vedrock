module session

import time
import protocol
import protocol.types
import server.event
import server.internal.gamedata
import server.internal.logger
import server.player
import server.world
import server.world.db

fn movement_isolation_test_session(mut hub Hub, mut wr WorldRuntime, pos types.Vector3) &NetworkSession {
	mut s := &NetworkSession{
		player:        player.new_player()
		hub:           hub
		runtime_id:    hub.allocate_runtime_id()
		spawned:       true
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}
	s.player.reset_position(pos)
	hub.add(s)
	// PlayerMoveTask requires world membership.
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

struct MovementIsolationBarrierTask {
	started chan bool
	release chan bool
}

fn (t MovementIsolationBarrierTask) run(mut tx WorldTx) {
	t.started <- true
	_ := <-t.release
}

fn test_stale_movement_task_dropped_after_world_switch() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'void', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := movement_isolation_test_session(mut hub, mut wr_a, types.Vector3{0, 0, 0})

	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	assert wr_a.submit(MovementIsolationBarrierTask{
		started: started
		release: release
	})
	_ := <-started

	stale_pos := types.Vector3{50.0, 0.0, 0.0}
	s.update_movement(stale_pos, 0.0, 0.0, 0.0)
	assert s.movement_scheduled == true

	// Simulate the session switching to world B while the task above is
	// still stuck behind A's stalled actor. A real change_world would also
	// register the session in B's players set as part of the same
	// transfer.
	gen := world_b.make_generator(hub.build_generator(world_b))
	s.set_world_binding(wr_b, gen)
	world_call[bool](mut wr_b, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	release <- true

	// A's actor now runs the stale PlayerMoveTask. It must not apply
	// stale_pos and must clear movement_scheduled so recovery is possible.
	deadline := time.now().add(2 * time.second)
	for time.now() < deadline && s.movement_scheduled {
		time.sleep(2 * time.millisecond)
	}
	assert s.movement_scheduled == false
	assert s.player.position() != stale_pos

	fresh_pos := types.Vector3{1.0, 2.0, 3.0}
	s.update_movement(fresh_pos, 0.0, 0.0, 0.0)
	deadline2 := time.now().add(2 * time.second)
	for time.now() < deadline2 && s.player.position() != fresh_pos {
		time.sleep(2 * time.millisecond)
	}
	assert s.player.position() == fresh_pos
}

struct CountingMoveHandler {
	event.NopHandler
mut:
	hits int
}

fn (mut h CountingMoveHandler) on_player_move(mut ctx event.Context[event.MoveData]) {
	h.hits++
}

// A handler on world B's event bus must never see movement from world A.
fn test_player_move_event_isolated_to_owning_world() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'void', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut handler_a := &CountingMoveHandler{}
	mut handler_b := &CountingMoveHandler{}
	wr_a.events.register(handler_a, .normal)
	wr_b.events.register(handler_b, .normal)

	mut s := movement_isolation_test_session(mut hub, mut wr_a, types.Vector3{0, 0, 0})
	s.update_movement(types.Vector3{5.0, 0.0, 0.0}, 0.0, 0.0, 0.0)

	deadline := time.now().add(2 * time.second)
	for time.now() < deadline && s.movement_scheduled {
		time.sleep(2 * time.millisecond)
	}
	assert handler_a.hits == 1
	assert handler_b.hits == 0
}

fn test_movement_broadcast_isolated_to_owning_world() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'void', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	target_pos := types.Vector3{5.0, 0.0, 0.0}
	mut observer_a := movement_isolation_test_session(mut hub, mut wr_a, target_pos)
	mut observer_b := movement_isolation_test_session(mut hub, mut wr_b, target_pos)
	mut a_transport := &FakeTransport{}
	mut b_transport := &FakeTransport{}
	observer_a.transport = a_transport
	observer_b.transport = b_transport

	mut mover := movement_isolation_test_session(mut hub, mut wr_a, types.Vector3{0, 0, 0})
	mover.update_movement(target_pos, 0.0, 0.0, 0.0)

	deadline := time.now().add(2 * time.second)
	for time.now() < deadline && mover.movement_scheduled {
		time.sleep(2 * time.millisecond)
	}

	mut sent_remaining := 2000 * time.millisecond
	for a_transport.sent.len == 0 {
		waited_from := time.now()
		select {
			_ := <-a_transport.sent_notify {}
			sent_remaining {
				break
			}
		}
		sent_remaining -= time.now() - waited_from
		if sent_remaining <= 0 {
			break
		}
	}

	mut a_saw_move := false
	for p in a_transport.sent {
		if p is protocol.MoveActorAbsolutePacket {
			a_saw_move = true
		}
	}
	assert a_saw_move

	for p in b_transport.sent {
		assert p !is protocol.MoveActorAbsolutePacket
	}
}
