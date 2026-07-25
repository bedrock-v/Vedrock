module session

import server.internal.auth
import server.internal.gamedata
import server.internal.logger
import server.player
import server.world
import server.world.db

fn player_ref_test_session(mut hub Hub, mut wr WorldRuntime, display_name string) &NetworkSession {
	mut transport := &FakeTransport{}
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

fn test_player_ref_missing_player_returns_none() {
	mut hub := new_hub(gamedata.GameData{})
	defer {
		hub.close_worlds()
	}

	if _ := hub.player_ref('nobody') {
		assert false
	}
}

fn test_player_ref_reports_captured_name_and_world() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('ref-test', none, 'void', world.overworld)
	hub.add_world(w)
	mut wr := hub.world_runtime('ref-test') or { panic('expected runtime') }
	defer {
		hub.close_worlds()
	}

	player_ref_test_session(mut hub, mut wr, 'Steve')

	p := hub.player_ref('Steve') or { panic('expected player ref') }
	assert p.name() == 'Steve'
	assert p.world().name() == 'ref-test'
}

fn test_player_ref_position_reflects_live_state() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('ref-position-test', none, 'void', world.overworld)
	hub.add_world(w)
	mut wr := hub.world_runtime('ref-position-test') or { panic('expected runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := player_ref_test_session(mut hub, mut wr, 'Alex')
	s.teleport(10, 70, -5)

	p := hub.player_ref('Alex') or { panic('expected player ref') }
	pos := p.position() or { panic('expected position') }
	assert pos.x == 10
	assert pos.y == 70
	assert pos.z == -5
}

fn test_player_ref_give_item_succeeds() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('ref-give-test', none, 'void', world.overworld)
	hub.add_world(w)
	mut wr := hub.world_runtime('ref-give-test') or { panic('expected runtime') }
	defer {
		hub.close_worlds()
	}

	player_ref_test_session(mut hub, mut wr, 'Herobrine')

	p := hub.player_ref('Herobrine') or { panic('expected player ref') }
	p.give_item('minecraft:air', 1) or { panic('expected give_item to succeed: ${err}') }
}

fn test_player_ref_operations_fail_after_world_switch() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('ref-switch-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('ref-switch-b', none, 'void', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('ref-switch-a') or { panic('expected world a runtime') }
	mut wr_b := hub.world_runtime('ref-switch-b') or { panic('expected world b runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := player_ref_test_session(mut hub, mut wr_a, 'Notch')
	p := hub.player_ref('Notch') or { panic('expected player ref') }
	assert p.world().name() == 'ref-switch-a'

	world_call[bool](mut wr_a, fn [s] (mut tx WorldTx) bool {
		tx.deregister_player(s.runtime_id)
		return true
	}) or { panic('deregistration rejected - world unexpectedly stopped') }
	s.set_world_binding(wr_b, world.VoidGenerator{})
	world_call[bool](mut wr_b, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	// was captured against world a's generation; it must not silently
	// resolve to wherever Notch now is.
	if _ := p.position() {
		assert false
	}
	if _ := p.give_item('minecraft:air', 1) {
		assert false
	}
	if _ := p.set_gamemode(1) {
		assert false
	}
}

fn test_player_ref_operations_fail_after_disconnect() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('ref-disconnect-test', none, 'void', world.overworld)
	hub.add_world(w)
	mut wr := hub.world_runtime('ref-disconnect-test') or { panic('expected runtime') }
	defer {
		hub.close_worlds()
	}

	mut s := player_ref_test_session(mut hub, mut wr, 'Zombie')
	p := hub.player_ref('Zombie') or { panic('expected player ref') }
	hub.remove(s.runtime_id)

	if _ := p.position() {
		assert false
	}
	if _ := p.disconnect('bye') {
		assert false
	}
}
