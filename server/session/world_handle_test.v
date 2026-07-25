module session

import time
import server.internal.gamedata
import server.world
import server.world.db

fn world_handle_wait_until(deadline_ms int, cond fn () bool) bool {
	deadline := time.now().add(deadline_ms * time.millisecond)
	for time.now() < deadline {
		if cond() {
			return true
		}
		time.sleep(2 * time.millisecond)
	}
	return cond()
}

fn test_world_handle_missing_world_returns_none() {
	mut hub := new_hub(gamedata.GameData{})
	defer {
		hub.close_worlds()
	}

	if _ := hub.world_handle('nope') {
		assert false
	}
}

fn test_world_handle_reports_name_and_dimension() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('handle-test', none, 'flat', world.overworld)
	hub.add_world(w)
	defer {
		hub.close_worlds()
	}

	handle := hub.world_handle('handle-test') or { panic('expected handle-test runtime') }
	assert handle.name() == 'handle-test'
	assert handle.dimension() == world.overworld
}

fn test_world_handle_set_block_round_trip() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('handle-block-test', none, 'void', world.overworld)
	hub.add_world(w)
	defer {
		hub.close_worlds()
	}

	mut handle := hub.world_handle('handle-block-test') or { panic('expected runtime') }
	handle.set_block(1, 64, 1, world.stone)!
	assert handle.block_at(1, 64, 1).network_id == world.stone.network_id
	// An unset position falls back to the void generator rather than
	// carrying over the override from a different position.
	assert handle.block_at(2, 64, 1).network_id == world.air.network_id
}

fn test_world_handle_tick_advances() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('handle-tick-test', none, 'void', world.overworld)
	hub.add_world(w)
	defer {
		hub.close_worlds()
	}

	handle := hub.world_handle('handle-tick-test') or { panic('expected runtime') }
	assert handle.current_tick() == 0

	mut wr := hub.world_runtime('handle-tick-test') or { panic('expected runtime') }
	wr.request_tick(5)
	assert world_handle_wait_until(2000, fn [handle] () bool {
		return handle.current_tick() == 5
	})
}

fn test_world_handle_set_block_rejected_after_shutdown() {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('handle-shutdown-test', none, 'void', world.overworld)
	hub.add_world(w)

	mut handle := hub.world_handle('handle-shutdown-test') or { panic('expected runtime') }
	hub.close_worlds()

	if _ := handle.set_block(0, 64, 0, world.stone) {
		assert false
	} else {
		assert err.msg().contains('shutting down')
	}
}
