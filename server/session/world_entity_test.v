module session

import time
import protocol.types
import server.entity
import server.event
import server.internal.gamedata
import server.internal.auth
import server.player
import server.world
import server.world.db
import protocol.current as proto

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

fn entity_isolation_test_session(mut hub Hub, mut transport FakeTransport, mut wr WorldRuntime, pos types.Vector3) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	mut s := &NetworkSession{
		player:        pl
		runtime_id:    hub.allocate_runtime_id()
		transport:     transport
		hub:           hub
		world:         wr.world
		world_runtime: wr
		generator:     world.VoidGenerator{}
	}
	s.player.reset_position(pos)
	hub.add(s)
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

// A mob spawned in world A's view distance broadcast must never reach a
// session in world B, even at the same numeric coordinates.
fn test_entity_spawn_broadcast_isolated_to_owning_world() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	hub.set_default_world('world-a')
	world_b := db.new_world('world-b', none, 'void', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	pos := types.Vector3{0.0, 10.0, 0.0}
	mut a_transport := &FakeTransport{}
	mut b_transport := &FakeTransport{}
	entity_isolation_test_session(mut hub, mut a_transport, mut wr_a, pos)
	entity_isolation_test_session(mut hub, mut b_transport, mut wr_b, pos)

	ok := hub.spawn_entity('pig', pos.x, pos.y, pos.z)
	assert ok
	assert wr_a.entities.count() == 1
	assert wr_b.entities.count() == 0
	assert wait_for_sent_len(a_transport, 1, 5000)

	mut a_saw_spawn := false
	for p in a_transport.sent {
		if p is proto.AddActorPacket {
			a_saw_spawn = true
		}
	}
	assert a_saw_spawn

	for p in b_transport.sent {
		assert p !is proto.AddActorPacket
	}
}

// EntityTickBarrierTask blocks a world's actor until released, signalling
// once it has actually started.
struct EntityTickBarrierTask {
	started chan bool
	release chan bool
}

fn (t EntityTickBarrierTask) name() string {
	return 'EntityTickBarrierTask'
}

fn (t EntityTickBarrierTask) run(mut tx WorldTx) {
	t.started <- true
	_ := <-t.release
}

fn entity_test_wait_until(deadline_ms int, cond fn () bool) bool {
	deadline := time.now().add(deadline_ms * time.millisecond)
	for time.now() < deadline {
		if cond() {
			return true
		}
		time.sleep(2 * time.millisecond)
	}
	return cond()
}

fn test_entity_tick_isolated_to_owning_world() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('stall-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	hub.set_default_world('stall-a')
	world_b := db.new_world('progress-b', none, 'void', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('stall-a') or { panic('expected stall-a runtime') }
	mut wr_b := hub.world_runtime('progress-b') or { panic('expected progress-b runtime') }
	defer {
		hub.close_worlds()
	}

	behaviour_a := entity.create('pig') or { panic('missing pig behaviour') }
	behaviour_b := entity.create('pig') or { panic('missing pig behaviour') }
	wr_a.entities.spawn(behaviour_a, types.Vector3{0, 10, 0})
	wr_b.entities.spawn(behaviour_b, types.Vector3{0, 10, 0})

	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	a_ok := wr_a.submit(EntityTickBarrierTask{
		started: started
		release: release
	})
	assert a_ok
	_ := <-started

	mut last_b_steps := wr_b.simulated_steps_count()
	for i in 0 .. 5 {
		hub.request_tick_all(i64(100 + i))
		assert entity_test_wait_until(3000, fn [wr_b, last_b_steps] () bool {
			return wr_b.simulated_steps_count() > last_b_steps
		})
		last_b_steps = wr_b.simulated_steps_count()
	}

	b_age := world_call[i64](mut wr_b, fn (mut tx WorldTx) i64 {
		return tx.wr.entities.snapshot()[0].age
	}) or { panic('sync call on B rejected - world unexpectedly stopped') }
	assert b_age > 0

	release <- true
	hub.request_tick_all(i64(500))
	assert entity_test_wait_until(2000, fn [wr_a] () bool {
		return wr_a.tick_snapshot() == max_world_catchup_ticks
	})
	a_age := world_call[i64](mut wr_a, fn (mut tx WorldTx) i64 {
		return tx.wr.entities.snapshot()[0].age
	}) or { panic('sync call on A rejected - world unexpectedly stopped') }
	assert a_age > 0
}

struct CountingEntitySpawnHandler {
	event.NopHandler
mut:
	hits int
}

fn (mut h CountingEntitySpawnHandler) on_entity_spawn(mut ctx event.Context[event.EntitySpawnData]) {
	h.hits++
}

struct CancelEntitySpawnHandler {
	event.NopHandler
}

fn (mut h CancelEntitySpawnHandler) on_entity_spawn(mut ctx event.Context[event.EntitySpawnData]) {
	ctx.cancel()
}

fn test_entity_spawn_event_isolated_to_owning_world() {
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

	mut handler_a := &CountingEntitySpawnHandler{}
	mut handler_b := &CountingEntitySpawnHandler{}
	wr_a.events.register(handler_a, .normal)
	wr_b.events.register(handler_b, .normal)

	behaviour := entity.create('pig') or { panic('missing pig behaviour') }
	task := SpawnEntityTask{
		behaviour: behaviour
		x:         0
		y:         10
		z:         0
	}
	assert wr_a.submit(task)
	spawned := <-task.result
	assert spawned

	assert handler_a.hits == 1
	assert handler_b.hits == 0
}

fn test_entity_spawn_event_cancellation_only_blocks_owning_world() {
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

	wr_a.events.register(&CancelEntitySpawnHandler{}, .normal)

	behaviour_a := entity.create('pig') or { panic('missing pig behaviour') }
	task_a := SpawnEntityTask{
		behaviour: behaviour_a
		x:         0
		y:         10
		z:         0
	}
	assert wr_a.submit(task_a)
	assert <-task_a.result == false
	assert wr_a.entities.count() == 0

	behaviour_b := entity.create('pig') or { panic('missing pig behaviour') }
	task_b := SpawnEntityTask{
		behaviour: behaviour_b
		x:         0
		y:         10
		z:         0
	}
	assert wr_b.submit(task_b)
	assert <-task_b.result == true
	assert wr_b.entities.count() == 1
}

struct CountingEntityDespawnHandler {
	event.NopHandler
mut:
	hits int
}

fn (mut h CountingEntityDespawnHandler) on_entity_despawn(mut ctx event.Context[event.EntityDespawnData]) {
	h.hits++
}

fn test_entity_despawn_event_isolated_to_owning_world() {
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

	mut handler_a := &CountingEntityDespawnHandler{}
	mut handler_b := &CountingEntityDespawnHandler{}
	wr_a.events.register(handler_a, .normal)
	wr_b.events.register(handler_b, .normal)

	behaviour_a := entity.create('pig') or { panic('missing pig behaviour') }
	behaviour_b := entity.create('pig') or { panic('missing pig behaviour') }
	entity_a := wr_a.entities.spawn(behaviour_a, types.Vector3{0, 10, 0})
	wr_b.entities.spawn(behaviour_b, types.Vector3{0, 10, 0})

	wr_a.entities.despawn(entity_a.runtime_id)

	assert handler_a.hits == 1
	assert handler_b.hits == 0
}

fn test_nearest_player_never_targets_another_worlds_player() {
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

	pos := types.Vector3{0.0, 10.0, 0.0}
	mut a_transport := &FakeTransport{}
	mut b_transport := &FakeTransport{}
	session_a := entity_isolation_test_session(mut hub, mut a_transport, mut wr_a, pos)
	entity_isolation_test_session(mut hub, mut b_transport, mut wr_b, pos)

	mut host_a := WorldEntityHost{
		wr: wr_a
	}
	rid := host_a.nearest_player(pos, 100.0) or { panic('expected to find world-a player') }
	assert rid == session_a.runtime_id
}

fn test_entity_hit_test_never_matches_another_worlds_player() {
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

	pos := types.Vector3{0.0, 10.0, 0.0}
	mut a_transport := &FakeTransport{}
	mut b_transport := &FakeTransport{}
	session_a := entity_isolation_test_session(mut hub, mut a_transport, mut wr_a, pos)
	session_b := entity_isolation_test_session(mut hub, mut b_transport, mut wr_b, pos)

	mut host_a := WorldEntityHost{
		wr: wr_a
	}
	mut host_b := WorldEntityHost{
		wr: wr_b
	}
	hit_a := host_a.entity_hit_test(pos, []u64{}) or { panic('expected a hit in world-a') }
	assert hit_a == session_a.runtime_id
	hit_b := host_b.entity_hit_test(pos, []u64{}) or { panic('expected a hit in world-b') }
	assert hit_b == session_b.runtime_id
}

fn test_damage_entity_never_reaches_another_worlds_player() {
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

	pos := types.Vector3{0.0, 10.0, 0.0}
	mut a_transport := &FakeTransport{}
	mut b_transport := &FakeTransport{}
	entity_isolation_test_session(mut hub, mut a_transport, mut wr_a, pos)
	mut session_b := entity_isolation_test_session(mut hub, mut b_transport, mut wr_b, pos)
	session_b.player.set_game_mode(.survival)
	before_health := session_b.player.health()

	mut host_a := WorldEntityHost{
		wr: wr_a
	}
	host_a.damage_entity(session_b.runtime_id, 5.0, 'test', 0, pos)

	assert session_b.player.health() == before_health
}

fn test_entity_hit_test_matches_players_and_mobs() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	mut wr := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	defer {
		hub.close_worlds()
	}

	player_pos := types.Vector3{0.0, 10.0, 0.0}
	mob_pos := types.Vector3{20.0, 10.0, 0.0}
	mut transport := &FakeTransport{}
	session := entity_isolation_test_session(mut hub, mut transport, mut wr, player_pos)
	mob := wr.entities.spawn(entity.PassiveBehaviour{
		network_id: 'minecraft:cow'
	}, mob_pos)

	mut host := WorldEntityHost{
		wr: wr
	}
	hit_player := host.entity_hit_test(player_pos, []u64{}) or {
		panic('expected a hit at player_pos')
	}
	assert hit_player == session.runtime_id
	hit_mob := host.entity_hit_test(mob_pos, []u64{}) or { panic('expected a hit at mob_pos') }
	assert hit_mob == mob.runtime_id
}

fn test_entity_position_resolves_both_player_and_mob() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	mut wr := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	defer {
		hub.close_worlds()
	}

	player_pos := types.Vector3{1.0, 5.0, 2.0}
	mob_pos := types.Vector3{9.0, 6.0, 3.0}
	mut transport := &FakeTransport{}
	session := entity_isolation_test_session(mut hub, mut transport, mut wr, player_pos)
	mob := wr.entities.spawn(entity.PassiveBehaviour{
		network_id: 'minecraft:pig'
	}, mob_pos)

	mut host := WorldEntityHost{
		wr: wr
	}
	got_player_pos := host.entity_position(session.runtime_id) or {
		panic('expected player position')
	}
	assert got_player_pos == player_pos
	got_mob_pos := host.entity_position(mob.runtime_id) or { panic('expected mob position') }
	assert got_mob_pos == mob_pos
	if _ := host.entity_position(99999) {
		assert false
	}
}

fn test_nearest_player_ignores_mobs_in_same_world() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	mut wr := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	defer {
		hub.close_worlds()
	}

	origin := types.Vector3{0.0, 10.0, 0.0}
	player_pos := types.Vector3{50.0, 10.0, 0.0}
	mut transport := &FakeTransport{}
	session := entity_isolation_test_session(mut hub, mut transport, mut wr, player_pos)
	wr.entities.spawn(entity.PassiveBehaviour{
		network_id: 'minecraft:chicken'
	}, types.Vector3{1.0, 10.0, 0.0})

	mut host := WorldEntityHost{
		wr: wr
	}
	rid := host.nearest_player(origin, 200.0) or { panic('expected to find the player') }
	assert rid == session.runtime_id
}
