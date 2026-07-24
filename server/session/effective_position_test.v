module session

import protocol.types
import server.internal.gamedata
import server.internal.logger
import server.player
import server.internal.auth
import server.world
import server.world.db

struct EffPosFillerTask {
	gate chan bool
}

fn (t EffPosFillerTask) run(mut tx WorldTx) {
	_ := <-t.gate
}

fn test_within_place_reach_uses_pending_mov_not_stale_pos() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut s := &NetworkSession{
		player:        player.new_player()
		hub:           hub
		runtime_id:    1
		spawned:       true
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}
	s.player.reset_position(types.Vector3{0.0, 0.0, 0.0})
	hub.add(s)

	gate := chan bool{cap: 1}
	wr.submit(EffPosFillerTask{ gate: gate })

	target_pos := types.BlockPosition{10, 0, 0}
	assert !s.within_place_reach(target_pos)
	s.update_movement(types.Vector3{10.0, 0.0, 0.0}, 0.0, 0.0, 0.0)

	assert s.within_place_reach(target_pos)
	gate <- true
}

fn test_effective_pos_uses_pending_movement_not_stale_confirmed() {
	mut hub := new_hub(gamedata.GameData{})
	target_world := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target_world)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut s := &NetworkSession{
		player:        &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		runtime_id:    1
		hub:           hub
		world:         target_world
		world_runtime: wr
		generator:     world.VoidGenerator{}
		spawned:       true
		log:           logger.new(.info)
	}
	s.player.reset_position(types.Vector3{0.0, player_eye_height, 0.0})
	hub.add(s)

	gate := chan bool{cap: 1}
	wr.submit(EffPosFillerTask{ gate: gate })

	assert s.effective_position() == types.Vector3{0.0, player_eye_height, 0.0}

	s.update_movement(types.Vector3{2.0, player_eye_height, 2.0}, 0.0, 0.0, 0.0)

	// The movement task itself is still queued behind the filler and has
	// not run.
	assert s.effective_position() == types.Vector3{2.0, player_eye_height, 2.0}
	gate <- true
}
