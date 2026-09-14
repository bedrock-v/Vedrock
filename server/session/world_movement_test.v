module session

import time
import bedrock_v.protocol.types
import server.event
import server.internal.gamedata
import server.internal.logger
import server.entity
import server.player
import server.world
import server.world.db
import bedrock_v.protocol.current as proto
import server.worldrt

fn movement_isolation_test_session(mut hub Hub, mut wr worldrt.WorldRuntime, pos types.Vector3) &NetworkSession {
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
	// Movement requires world membership.
	worldrt.world_call[bool]('test', mut wr, fn [s] (mut tx worldrt.WorldTx) bool {
		register_player(mut tx, s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

struct CountingMoveHandler {
	player.NopHandler
mut:
	hits int
}

fn (mut h CountingMoveHandler) on_player_move(mut ctx event.Context[player.MoveData]) {
	h.hits++
}

// A handler on another player must never see this player's movement.
fn test_player_move_event_reaches_only_the_moving_player() {
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

	mut s := movement_isolation_test_session(mut hub, mut wr_a, types.Vector3{0, 0, 0})
	s.handle(handler_a)
	mut other := movement_isolation_test_session(mut hub, mut wr_b, types.Vector3{0, 0, 0})
	other.handle(handler_b)

	in_world(mut s, fn [mut s] (mut tx worldrt.WorldTx) ! {
		s.update_movement(mut tx, types.Vector3{5.0, 0.0, 0.0}, 0.0, 0.0, 0.0, false)
	})!

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
	observer_a.conn.transport = a_transport
	observer_b.conn.transport = b_transport

	mut mover := movement_isolation_test_session(mut hub, mut wr_a, types.Vector3{0, 0, 0})
	in_world(mut mover, fn [mut mover, target_pos] (mut tx worldrt.WorldTx) ! {
		mover.update_movement(mut tx, target_pos, 0.0, 0.0, 0.0, false)
	})!

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
		if p is proto.MoveActorAbsolutePacket {
			a_saw_move = true
		}
	}
	assert a_saw_move

	for p in b_transport.sent {
		assert p !is proto.MoveActorAbsolutePacket
	}
}

fn viewer_test_session(mut hub Hub, mut wr worldrt.WorldRuntime, mut transport FakeTransport) &NetworkSession {
	mut s := &NetworkSession{
		player:        player.new_player()
		hub:           hub
		runtime_id:    hub.allocate_runtime_id()
		spawned:       true
		conn:          &Conn{
			transport: transport
		}
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}
	hub.add(s)
	s.activate_outbound()
	worldrt.world_call[bool]('test', mut wr, fn [s] (mut tx worldrt.WorldTx) bool {
		register_player(mut tx, s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn drain_until_sent(mut transport FakeTransport, budget time.Duration) {
	mut remaining := budget
	for transport.sent.len == 0 && remaining > 0 {
		waited_from := time.now()
		select {
			_ := <-transport.sent_notify {}
			remaining {
				break
			}
		}
		remaining -= time.now() - waited_from
	}
}

fn test_teleport_snaps_its_client_and_moves_body_for_others() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}

	mut mover_transport := &FakeTransport{}
	mut observer_transport := &FakeTransport{}
	mut mover := viewer_test_session(mut hub, mut wr, mut mover_transport)
	viewer_test_session(mut hub, mut wr, mut observer_transport)

	rid := mover.runtime_id
	epoch := mover.world_binding().epoch
	moved := worldrt.world_call[bool]('test', mut wr, fn [rid, epoch] (mut tx worldrt.WorldTx) bool {
		mut s := player_for_id(mut tx, entity.new_actor_id(rid, epoch)) or { return false }
		s.player.teleport(mut tx, types.Vector3{12.0, 70.0, -4.0})
		return true
	}) or { panic('world unexpectedly stopped') }
	assert moved

	drain_until_sent(mut mover_transport, 2000 * time.millisecond)
	drain_until_sent(mut observer_transport, 2000 * time.millisecond)

	mut mover_snapped := false
	for p in mover_transport.sent {
		assert p !is proto.MoveActorAbsolutePacket
		if p is proto.MovePlayerPacket {
			mover_snapped = true
		}
	}
	assert mover_snapped, 'the teleported player was not told to snap'

	mut observer_saw_move := false
	for p in observer_transport.sent {
		assert p !is proto.MovePlayerPacket
		if p is proto.MoveActorAbsolutePacket {
			observer_saw_move = true
		}
	}
	assert observer_saw_move, 'the other player was not shown the move'
}

// in_world runs f on the actor of the world s is in, the way a play packet is
// handled and returns what f returned.
fn in_world(mut s NetworkSession, f fn (mut tx worldrt.WorldTx) !) ! {
	mut wr := s.current_world_runtime()
	outcome := worldrt.world_call[ExecOutcome]('test', mut wr, fn [f] (mut tx worldrt.WorldTx) ExecOutcome {
		f(mut tx) or {
			return ExecOutcome{
				failed: true
				msg:    err.msg()
			}
		}
		return ExecOutcome{}
	}) or { return error('world stopped') }
	if outcome.failed {
		return error(outcome.msg)
	}
}
