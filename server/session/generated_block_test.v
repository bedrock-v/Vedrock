module session

import server.internal.auth
import server.internal.gamedata
import server.player
import server.world
import server.world.db

// tree_position finds a block the generator only produces while building a
// whole column - a tree, in practice. Its per block query answers air there, so
// it is exactly the case a block read must not be taken from.
fn tree_position(gen world.Generator, chunk world.Chunk) ?(int, int, int, int) {
	for x in 0 .. 16 {
		for z in 0 .. 16 {
			for y in 0 .. 120 {
				id := chunk.block_id(x, y, z)
				if id != world.air.network_id && gen.block_at(x, y, z) != id {
					return x, y, z, id
				}
			}
		}
	}
	return none
}

// A player mining a tree gets no break animation and no particles when the
// server reads air where the client was sent a log: the break never starts.
fn test_block_at_sees_the_terrain_the_client_was_sent() {
	mut hub := new_hub(gamedata.GameData{})
	mut transport := &FakeTransport{}
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	pl.set_game_mode(.survival)

	gen := world.new_generator('normal')
	wld := db.new_world('trees', none, 'normal', world.overworld)
	hub.add_world(wld)
	mut wr := hub.world_runtime('trees') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}
	chunk := gen.generate(0, 0)
	x, y, z, id := tree_position(gen, chunk) or {
		assert false, 'no populated block in the first column'
		return
	}

	mut s := &NetworkSession{
		player:        pl
		runtime_id:    1
		conn: &Conn{ transport: transport }
		hub:           hub
		world:         wld
		world_runtime: wr
		generator:     gen
	}
	hub.add(s)

	assert s.block_at(x, y, z) == id
}
