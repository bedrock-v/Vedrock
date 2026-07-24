module session

import server.event
import server.internal.gamedata
import server.internal.logger
import server.player
import server.internal.auth
import server.world
import server.world.db

fn combat_world_test_session(mut hub Hub, mut wr WorldRuntime, name string, health f32) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: name
	}
	pl.set_health(health)
	mut s := &NetworkSession{
		player:        pl
		hub:           hub
		runtime_id:    hub.allocate_runtime_id()
		transport:     &FakeTransport{}
		spawned:       true
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}
	hub.add(s)
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

struct CountingAttackHandler {
	event.NopHandler
mut:
	hits int
}

fn (mut h CountingAttackHandler) on_player_attack(mut ctx event.Context[event.AttackData]) {
	h.hits++
}

struct CountingDeathHandler {
	event.NopHandler
mut:
	hits int
}

fn (mut h CountingDeathHandler) on_player_death(mut ctx event.Context[event.DeathData]) {
	h.hits++
}

// player_attack must dispatch on the world both combatants are actually in,
// never a second (or the wrong) world's bus.
fn test_player_attack_event_isolated_to_owning_world() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut handler_a := &CountingAttackHandler{}
	mut handler_b := &CountingAttackHandler{}
	wr_a.events.register(handler_a, .normal)
	wr_b.events.register(handler_b, .normal)

	mut attacker := combat_world_test_session(mut hub, mut wr_a, 'Alex', 20)
	mut victim := combat_world_test_session(mut hub, mut wr_a, 'Steve', 20)

	attacker.handle_attack(victim.runtime_id)!
	world_call[bool](mut wr_a, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected') }

	assert handler_a.hits == 1
	assert handler_b.hits == 0
}

fn test_attack_cross_world_victim_produces_no_effect() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut attacker := combat_world_test_session(mut hub, mut wr_a, 'Alex', 20)
	mut victim := combat_world_test_session(mut hub, mut wr_b, 'Steve', 20)

	attacker.handle_attack(victim.runtime_id)!
	world_call[bool](mut wr_a, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected') }

	assert victim.player.health() == 20
}

fn test_attack_stale_epoch_produces_no_effect() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut attacker := combat_world_test_session(mut hub, mut wr_a, 'Alex', 20)
	mut victim := combat_world_test_session(mut hub, mut wr_a, 'Steve', 20)

	stale_epoch := attacker.world_binding().epoch
	assert attacker.change_world('world-b', 0.0, 0.0, 0.0)

	task := PlayerAttackTask{
		attacker_runtime_id: attacker.runtime_id
		attacker_epoch:      stale_epoch
		victim_runtime_id:   victim.runtime_id
		damage:              10.0
	}
	assert wr_a.submit(task)
	world_call[bool](mut wr_a, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected') }

	assert victim.player.health() == 20
}

fn test_kill_stale_epoch_produces_no_effect() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := combat_world_test_session(mut hub, mut wr_a, 'Alex', 20)

	stale_epoch := s.world_binding().epoch
	assert s.change_world('world-b', 0.0, 0.0, 0.0)

	task := PlayerKillTask{
		runtime_id: s.runtime_id
		epoch:      stale_epoch
	}
	assert wr_a.submit(task)
	world_call[bool](mut wr_a, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected') }

	assert s.player.health() == 20
	assert !s.player.is_dead()
}

fn test_respawn_stale_epoch_produces_no_effect() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := combat_world_test_session(mut hub, mut wr_a, 'Alex', 20)
	s.player.set_health(0)
	s.player.set_dead(true)

	stale_epoch := s.world_binding().epoch
	assert s.change_world('world-b', 0.0, 0.0, 0.0)

	task := PlayerRespawnTask{
		runtime_id: s.runtime_id
		epoch:      stale_epoch
	}
	assert wr_a.submit(task)
	world_call[bool](mut wr_a, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected') }

	assert s.player.is_dead()
	assert s.player.health() == 0
}

fn test_player_death_event_isolated_to_owning_world() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('world-a', none, 'flat', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('world-b', none, 'flat', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('world-a') or { panic('expected world-a runtime') }
	mut wr_b := hub.world_runtime('world-b') or { panic('expected world-b runtime') }
	defer {
		hub.close_worlds()
	}

	mut handler_a := &CountingDeathHandler{}
	mut handler_b := &CountingDeathHandler{}
	wr_a.events.register(handler_a, .normal)
	wr_b.events.register(handler_b, .normal)

	mut s := combat_world_test_session(mut hub, mut wr_a, 'Alex', 20)
	s.kill()
	world_call[bool](mut wr_a, fn (mut tx WorldTx) bool {
		return true
	}) or { panic('sync barrier rejected') }

	assert s.player.is_dead()
	assert handler_a.hits == 1
	assert handler_b.hits == 0
}
