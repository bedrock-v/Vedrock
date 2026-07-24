module session

import server.internal.gamedata
import server.world
import server.world.db

fn test_world_registry_add_get_remove() {
	mut r := new_world_registry()
	assert r.len() == 0

	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('reg-test', none, 'flat', world.overworld)
	mut wr := new_world_runtime(hub, w)
	defer {
		wr.shutdown()
	}

	r.add(wr)
	assert r.len() == 1
	assert r.names() == ['reg-test']

	got := r.get('reg-test') or { panic('expected registry to find reg-test') }
	assert got.world.name == 'reg-test'

	assert r.get('does-not-exist') == none

	removed := r.remove('reg-test') or { panic('expected remove to find reg-test') }
	assert removed.world.name == 'reg-test'
	assert r.len() == 0
	assert r.get('reg-test') == none
}

fn test_hub_world_and_world_runtime_agree() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('paired', none, 'flat', world.overworld)
	hub.add_world(w)
	hub.set_default_world('paired')
	defer {
		hub.close_worlds()
	}

	via_world := hub.world('paired') or { panic('expected world lookup to succeed') }
	via_runtime := hub.world_runtime('paired') or {
		panic('expected world_runtime lookup to succeed')
	}
	// The invariant this pairing exists to guarantee: both routes resolve to
	// the exact same underlying db.World, never two different snapshots.
	assert via_runtime.world.name == via_world.name
	assert voidptr(via_runtime.world) == voidptr(via_world)
}

fn test_session_world_binding_stays_paired_after_world_switch() {
	mut hub := new_hub(gamedata.GameData{})
	main_world := db.new_world('main', none, 'flat', world.overworld)
	hub.add_world(main_world)
	hub.set_default_world('main')
	other_world := db.new_world('other', none, 'flat', world.overworld)
	hub.add_world(other_world)
	defer {
		hub.close_worlds()
	}

	other_wr := hub.world_runtime('other') or { panic('expected other world runtime') }
	mut s := &NetworkSession{
		hub: hub
	}
	s.set_world_binding(other_wr, world.FlatGenerator{})

	binding := s.world_binding()
	// The invariant set_world_binding/world_binding exist to guarantee:
	// world_runtime.world and world can never disagree because they're
	// only ever written together and read together as one unit.
	assert voidptr(binding.world_runtime.world) == voidptr(binding.world)
	assert binding.world.name == 'other'
	assert s.current_world_runtime().world.name == 'other'
}
