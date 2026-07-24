module session

import time
import protocol
import server.internal.gamedata
import server.internal.auth
import server.internal.logger
import server.player
import server.world
import server.world.db

fn wait_for_sent_len(transport &FakeTransport, want int, timeout_ms int) bool {
	mut remaining := timeout_ms * time.millisecond
	for transport.sent.len < want {
		waited_from := time.now()
		select {
			_ := <-transport.sent_notify {}
			remaining {
				return transport.sent.len >= want
			}
		}
		remaining -= time.now() - waited_from
		if remaining <= 0 {
			return transport.sent.len >= want
		}
	}
	return true
}

fn wr_has_player(mut wr WorldRuntime, rid u64) bool {
	return world_call[bool](mut wr, fn [rid] (mut tx WorldTx) bool {
		return rid in tx.wr.players
	}) or { false }
}

fn membership_test_session(mut hub Hub, wr &WorldRuntime) &NetworkSession {
	mut transport := &FakeTransport{}
	return membership_test_session_with_transport(mut hub, wr, 'Alex', mut transport)
}

fn membership_test_session_with_transport(mut hub Hub, wr &WorldRuntime, name string, mut transport FakeTransport) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: name
	}
	mut s := &NetworkSession{
		player:        pl
		hub:           hub
		runtime_id:    hub.allocate_runtime_id()
		transport:     transport
		spawned:       false
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}
	return s
}

fn add_player_packet_count(transport &FakeTransport, runtime_id u64) int {
	mut count := 0
	for p in transport.sent {
		if p is protocol.AddPlayerPacket {
			if p.actor_runtime_id == runtime_id {
				count++
			}
		}
	}
	return count
}

fn test_initial_join_registers_player_in_world() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := membership_test_session(mut hub, wr)
	assert !wr_has_player(mut wr, s.runtime_id)

	s.handle_player_initialized(protocol.SetLocalPlayerAsInitializedPacket{})!

	assert wr_has_player(mut wr, s.runtime_id)
}

fn test_initial_join_releases_pending_name_reservation() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := membership_test_session(mut hub, wr)
	assert hub.reserve_player_name('Alex')
	assert hub.admission_count() == 1

	s.handle_player_initialized(protocol.SetLocalPlayerAsInitializedPacket{})!

	assert wr_has_player(mut wr, s.runtime_id)
	assert hub.admission_count() == 1
	assert !hub.reserve_player_name('Alex')
}

fn test_initial_join_exchanges_player_view_only_with_current_world() {
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

	mut far_transport := &FakeTransport{}
	mut far := membership_test_session_with_transport(mut hub, wr_a, 'Far', mut far_transport)
	far.spawned = true
	hub.add(far)
	world_call[bool](mut wr_a, fn [far] (mut tx WorldTx) bool {
		tx.register_player(far)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	mut near_transport := &FakeTransport{}
	mut near := membership_test_session_with_transport(mut hub, wr_b, 'Near', mut near_transport)
	near.spawned = true
	hub.add(near)
	world_call[bool](mut wr_b, fn [near] (mut tx WorldTx) bool {
		tx.register_player(near)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	mut joining_transport := &FakeTransport{}
	mut joining := membership_test_session_with_transport(mut hub, wr_b, 'Joining', mut
		joining_transport)
	joining.handle_player_initialized(protocol.SetLocalPlayerAsInitializedPacket{})!
	// handle_player_initialized's join broadcasts and per observer
	// "existing players" packets now land asynchronously through each
	// session's own outbound writer, not synchronously inside the call.
	assert wait_for_sent_len(joining_transport, 1, 2000)
	assert wait_for_sent_len(near_transport, 1, 2000)

	assert add_player_packet_count(joining_transport, far.runtime_id) == 0
	assert add_player_packet_count(joining_transport, near.runtime_id) == 1
	assert add_player_packet_count(far_transport, joining.runtime_id) == 0
	assert add_player_packet_count(near_transport, joining.runtime_id) == 1
}

// A -> B: the source world must lose the membership and the destination
// must gain it. Never both, never neither.
fn test_world_switch_transfers_player_membership() {
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

	mut s := membership_test_session(mut hub, wr_a)
	s.handle_player_initialized(protocol.SetLocalPlayerAsInitializedPacket{})!
	assert wr_has_player(mut wr_a, s.runtime_id)
	assert !wr_has_player(mut wr_b, s.runtime_id)

	ok := s.change_world('world-b', 0.0, 0.0, 0.0)
	assert ok

	assert !wr_has_player(mut wr_a, s.runtime_id)
	assert wr_has_player(mut wr_b, s.runtime_id)
}

// A player returning to a world must be registered there again and removed
// from the world it left. Epoch checks distinguish this new registration
// from stale tasks created during the player's previous stay.
fn test_world_switch_away_and_back_restores_membership() {
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

	mut s := membership_test_session(mut hub, wr_a)
	s.handle_player_initialized(protocol.SetLocalPlayerAsInitializedPacket{})!
	epoch_first_a := s.world_binding().epoch

	assert s.change_world('world-b', 0.0, 0.0, 0.0)
	assert s.change_world('world-a', 0.0, 0.0, 0.0)
	epoch_second_a := s.world_binding().epoch

	assert wr_has_player(mut wr_a, s.runtime_id)
	assert !wr_has_player(mut wr_b, s.runtime_id)
	assert epoch_second_a != epoch_first_a
}

fn test_disconnect_deregisters_player() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := membership_test_session(mut hub, wr)
	s.handle_player_initialized(protocol.SetLocalPlayerAsInitializedPacket{})!
	assert wr_has_player(mut wr, s.runtime_id)

	s.leave()

	assert !wr_has_player(mut wr, s.runtime_id)
}

fn test_failed_destination_registration_disconnects_session() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'void', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }

	mut s := membership_test_session(mut hub, wr_a)
	s.handle_player_initialized(protocol.SetLocalPlayerAsInitializedPacket{})!

	// Shut down B's actor directly, so world_runtime('world-b') still
	// resolves it but any submission to it is now rejected.
	wr_b.shutdown()
	defer {
		wr_a.shutdown()
	}

	ok := s.change_world('world-b', 0.0, 0.0, 0.0)

	assert !ok
	assert s.state == .closed
}
