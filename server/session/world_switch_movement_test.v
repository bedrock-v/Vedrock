module session

import bedrock_v.protocol.current as proto
import bedrock_v.protocol.types
import server.internal.gamedata
import server.player
import server.internal.auth
import server.world
import server.world.db
import server.internal.logger

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

	sync_pos := s.player.position()
	s.handle_world_packet(move_packet(sync_pos))!

	// A real client keeps sending movement continuously after the switch.
	mut last := sync_pos
	for i in 0 .. 200 {
		last = types.Vector3{sync_pos.x + f32(i) * 0.1, sync_pos.y, sync_pos.z}
		s.handle_world_packet(move_packet(last))!
	}
	assert s.player.position() == last
	assert s.movement_scheduled == false

	further := types.Vector3{last.x + 1.0, last.y, last.z}
	s.handle_world_packet(move_packet(further))!
	assert s.player.position() == further
}

// move_packet is a movement report placing the player at pos.
fn move_packet(pos types.Vector3) &proto.MovePlayerPacket {
	mut p := &proto.MovePlayerPacket{}
	p.position[0] = pos.x
	p.position[1] = pos.y
	p.position[2] = pos.z
	return p
}
