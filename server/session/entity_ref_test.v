module session

import time
import protocol.version.v662.packets as packets_662
import types
import server.entity
import server.internal.auth
import server.internal.gamedata
import server.internal.logger
import server.player
import server.world
import server.world.db

fn entity_ref_test_session(mut hub Hub, mut wr WorldRuntime, mut transport FakeTransport, display_name string) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: display_name
	}
	mut s := &NetworkSession{
		player:        pl
		runtime_id:    hub.allocate_runtime_id()
		spawned:       true
		transport:     transport
		hub:           hub
		world:         wr.world
		world_runtime: wr
		generator:     world.VoidGenerator{}
		log:           logger.new(.info)
	}
	hub.add(s)
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn entity_ref_wait_for_sent_len(transport &FakeTransport, want int, timeout_ms int) bool {
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

fn entity_ref_test_world() (&Hub, &WorldRuntime) {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('entity-ref-test', none, 'void', world.overworld)
	hub.add_world(w)
	wr := hub.world_runtime('entity-ref-test') or { panic('expected entity-ref-test runtime') }
	return hub, wr
}

fn test_entity_ref_missing_entity_returns_none() {
	mut hub, wr := entity_ref_test_world()
	defer {
		hub.close_worlds()
	}
	mut handle := hub.world_handle('entity-ref-test') or { panic('expected handle') }

	if _ := handle.entity_ref(99999) {
		assert false
	}
	_ := wr
}

fn test_entity_ref_never_resolves_a_registered_player() {
	mut hub, mut wr := entity_ref_test_world()
	defer {
		hub.close_worlds()
	}
	mut handle := hub.world_handle('entity-ref-test') or { panic('expected handle') }

	mut transport := &FakeTransport{}
	s := entity_ref_test_session(mut hub, mut wr, mut transport, 'Watcher')

	if _ := handle.entity_ref(s.runtime_id) {
		assert false
	}
}

fn test_entity_ref_reports_world_and_valid() {
	mut hub, mut wr := entity_ref_test_world()
	defer {
		hub.close_worlds()
	}
	mut handle := hub.world_handle('entity-ref-test') or { panic('expected handle') }

	e := wr.entities.spawn(entity.PassiveBehaviour{
		network_id: 'minecraft:cow'
	}, types.Vector3{10, 64, 5})

	ref := handle.entity_ref(e.runtime_id) or { panic('expected entity ref') }
	assert ref.valid()
	assert ref.world().name() == 'entity-ref-test'
}

fn test_entity_ref_position_matches_spawn_position() {
	mut hub, mut wr := entity_ref_test_world()
	defer {
		hub.close_worlds()
	}
	mut handle := hub.world_handle('entity-ref-test') or { panic('expected handle') }

	e := wr.entities.spawn(entity.PassiveBehaviour{
		network_id: 'minecraft:pig'
	}, types.Vector3{1, 65, 2})

	ref := handle.entity_ref(e.runtime_id) or { panic('expected entity ref') }
	pos := ref.position() or { panic('expected position') }
	assert pos.x == 1
	assert pos.y == 65
	assert pos.z == 2
}

fn test_entity_ref_teleport_moves_and_broadcasts() {
	mut hub, mut wr := entity_ref_test_world()
	defer {
		hub.close_worlds()
	}
	mut handle := hub.world_handle('entity-ref-test') or { panic('expected handle') }

	e := wr.entities.spawn(entity.PassiveBehaviour{
		network_id: 'minecraft:cow'
	}, types.Vector3{})

	mut transport := &FakeTransport{}
	entity_ref_test_session(mut hub, mut wr, mut transport, 'Watcher')

	ref := handle.entity_ref(e.runtime_id) or { panic('expected entity ref') }
	ref.teleport(types.Vector3{5, 70, 9})!

	pos := ref.position() or { panic('expected position') }
	assert pos.x == 5
	assert pos.y == 70
	assert pos.z == 9

	found_move := entity_ref_wait_for_sent_len(transport, 1, 2000)
	assert found_move
	mut saw_move := false
	for p in transport.sent {
		if p is packets_662.MoveActorAbsolutePacket {
			saw_move = true
		}
	}
	assert saw_move
}

fn test_entity_ref_damage_kills_when_fatal() {
	mut hub, mut wr := entity_ref_test_world()
	defer {
		hub.close_worlds()
	}
	mut handle := hub.world_handle('entity-ref-test') or { panic('expected handle') }

	e := wr.entities.spawn(entity.PassiveBehaviour{
		network_id: 'minecraft:chicken'
	}, types.Vector3{})

	ref := handle.entity_ref(e.runtime_id) or { panic('expected entity ref') }
	ref.damage(100, true, 0)!

	dead := world_call[bool](mut wr, fn [e] (mut tx WorldTx) bool {
		target := tx.wr.entities.by_runtime_id(e.runtime_id) or { return false }
		return target.is_dead()
	}) or { panic('read rejected - world unexpectedly stopped') }
	assert dead
}

fn test_entity_ref_close_removes_the_entity() {
	mut hub, mut wr := entity_ref_test_world()
	defer {
		hub.close_worlds()
	}
	mut handle := hub.world_handle('entity-ref-test') or { panic('expected handle') }

	e := wr.entities.spawn(entity.PassiveBehaviour{
		network_id: 'minecraft:sheep'
	}, types.Vector3{})

	ref := handle.entity_ref(e.runtime_id) or { panic('expected entity ref') }
	ref.close()!

	assert !ref.valid()
	if _ := ref.position() {
		assert false
	}
	if _ := ref.close() {
		assert false
	}
}
