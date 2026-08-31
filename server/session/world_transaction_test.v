module session

import server.internal.auth
import server.internal.gamedata
import server.internal.logger
import server.player
import server.world
import server.world.db

fn wtx_test_world() (&Hub, &WorldRuntime) {
	mut hub := new_hub(gamedata.GameData{})
	w := db.new_world('world-transaction-test', none, 'void', world.overworld)
	hub.add_world(w)
	wr := hub.world_runtime('world-transaction-test') or { panic('expected runtime') }
	return hub, wr
}

fn wtx_test_session(mut hub Hub, mut wr WorldRuntime, display_name string) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: display_name
	}
	mut s := &NetworkSession{
		player:        pl
		runtime_id:    hub.allocate_runtime_id()
		spawned:       true
		transport:     &FakeTransport{}
		hub:           hub
		world:         wr.world
		world_runtime: wr
		generator:     world.VoidGenerator{}
		log:           logger.new(.info)
	}
	hub.add(s)
	world_call[bool]('test', mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn test_exec_commits_block_change() {
	mut hub, mut wr := wtx_test_world()
	defer {
		hub.close_worlds()
	}
	mut handle := hub.world_handle('world-transaction-test') or { panic('expected handle') }

	handle.exec(fn (mut tx WorldTransaction) ! {
		tx.set_block(1, 2, 3, world.stone)!
	}) or { panic('expected exec to succeed: ${err}') }

	assert handle.block_at(1, 2, 3).network_id == world.stone.network_id
	_ := wr
}

fn test_exec_applies_multiple_mutations() {
	mut hub, mut wr := wtx_test_world()
	defer {
		hub.close_worlds()
	}
	mut handle := hub.world_handle('world-transaction-test') or { panic('expected handle') }

	handle.exec(fn (mut tx WorldTransaction) ! {
		tx.set_block(0, 0, 0, world.stone)!
		tx.set_block(1, 0, 0, world.stone)!
		assert tx.block_at(0, 0, 0).network_id == world.stone.network_id
		assert tx.block_at(1, 0, 0).network_id == world.stone.network_id
	}) or { panic('expected exec to succeed: ${err}') }

	assert handle.block_at(0, 0, 0).network_id == world.stone.network_id
	assert handle.block_at(1, 0, 0).network_id == world.stone.network_id
	_ := wr
}

fn test_exec_returns_callback_error_without_rollback() {
	mut hub, mut wr := wtx_test_world()
	defer {
		hub.close_worlds()
	}
	mut handle := hub.world_handle('world-transaction-test') or { panic('expected handle') }

	mut failed := false
	mut msg := ''
	handle.exec(fn (mut tx WorldTransaction) ! {
		tx.set_block(4, 4, 4, world.stone)!
		return error('deliberate failure')
	}) or {
		failed = true
		msg = err.msg()
	}
	assert failed
	assert msg == 'deliberate failure'
	assert handle.block_at(4, 4, 4).network_id == world.stone.network_id
	_ := wr
}
