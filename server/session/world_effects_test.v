module session

import time
import server.effect
import server.internal.gamedata
import server.internal.logger
import server.player
import server.internal.auth
import server.world
import server.world.db

struct EffectsTickBarrierTask {
	started chan bool
	release chan bool
}

fn (t EffectsTickBarrierTask) run(mut tx WorldTx) {
	t.started <- true
	_ := <-t.release
}

fn effects_tick_test_session(mut hub Hub, mut wr WorldRuntime, name string, health f32) &NetworkSession {
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

fn effects_test_wait_until(deadline_ms int, cond fn () bool) bool {
	deadline := time.now().add(deadline_ms * time.millisecond)
	for time.now() < deadline {
		if cond() {
			return true
		}
		time.sleep(2 * time.millisecond)
	}
	return cond()
}

// A player's regeneration in a stalled world doesn't advance while a player
// in a live concurrently ticking world keeps regenerating.
fn test_effects_tick_isolated_to_owning_world() {
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

	mut player_a := effects_tick_test_session(mut hub, mut wr_a, 'Alex', 10)
	mut player_b := effects_tick_test_session(mut hub, mut wr_b, 'Steve', 10)

	rid_a := player_a.runtime_id
	world_call[bool](mut wr_a, fn [rid_a] (mut tx WorldTx) bool {
		mut s := tx.player_for_epoch(rid_a, 0) or { return false }
		s.apply_add_effect(mut tx.wr, effect.new(effect.regeneration, 1, 5 * time.second))
		return true
	}) or { panic('sync barrier rejected') }
	rid_b := player_b.runtime_id
	world_call[bool](mut wr_b, fn [rid_b] (mut tx WorldTx) bool {
		mut s := tx.player_for_epoch(rid_b, 0) or { return false }
		s.apply_add_effect(mut tx.wr, effect.new(effect.regeneration, 1, 5 * time.second))
		return true
	}) or { panic('sync barrier rejected') }

	started := chan bool{cap: 1}
	release := chan bool{cap: 1}
	a_ok := wr_a.submit(EffectsTickBarrierTask{
		started: started
		release: release
	})
	assert a_ok
	_ := <-started

	health_a_before := player_a.player.health()

	for i in 0 .. 5 {
		hub.request_tick_all(i64(100 + i))
		assert effects_test_wait_until(1000, fn [player_b, health_a_before] () bool {
			return player_b.player.health() > health_a_before
		})
	}

	assert player_a.player.health() == health_a_before

	release <- true
	assert effects_test_wait_until(2000, fn [player_a, health_a_before] () bool {
		return player_a.player.health() > health_a_before
	})
}
