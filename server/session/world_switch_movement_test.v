module session

import protocol.types
import server.internal.gamedata
import server.player
import server.internal.auth
import server.world
import server.world.db
import server.internal.logger
import time

fn test_pos_keeps_tracking_after_world_switch_roundtrip() {
	mut hub := new_hub(gamedata.GameData{})
	main_world := db.new_world('world', none, 'flat', world.overworld)
	hub.add_world(main_world)
	hub.set_default_world('world')
	end_world := db.new_world('end', none, 'flat', world.overworld)
	hub.add_world(end_world)

	mut s := &NetworkSession{
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		runtime_id: 1
		hub:        hub
		world:      main_world
		generator:  world.FlatGenerator{}
		spawned:    true
		log:        logger.new(.info)
	}
	s.player.reset_position(types.Vector3{0.0, 5.0, 0.0})
	hub.add(s)

	// world_teleport completes the transfer synchronously before returning, so
	// no sync barrier is needed.
	s.world_teleport('end') or { panic('teleport to end failed: ${err}') }
	assert s.world_name() == 'end'

	s.world_teleport('world') or { panic('teleport back to world failed: ${err}') }
	assert s.world_name() == 'world'

	// Simulate a real client continuing to send PlayerAuthInputPacket
	// continuously after the world switch.
	mut last := types.Vector3{}
	for i in 0 .. 200 {
		last = types.Vector3{f32(i) * 0.1, 5.0, 0.0}
		s.update_movement(last, 0.0, 0.0, 0.0)
	}

	deadline := time.now().add(5 * time.second)
	for time.now() < deadline && (s.player.position() != last || s.movement_scheduled) {
		time.sleep(2 * time.millisecond)
	}
	assert s.player.position() == last
	assert s.movement_scheduled == false

	further := types.Vector3{last.x + 1.0, last.y, last.z}
	s.update_movement(further, 0.0, 0.0, 0.0)
	deadline2 := time.now().add(5 * time.second)
	for time.now() < deadline2 && s.player.position() != further {
		time.sleep(2 * time.millisecond)
	}
	assert s.player.position() == further
}
