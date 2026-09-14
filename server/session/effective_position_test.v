module session

import bedrock_v.protocol.current as proto
import bedrock_v.protocol.types
import server.internal.gamedata
import server.internal.logger
import server.player
import server.world
import server.world.db
import server.worldrt

// A block action is judged for reach from the movement handled before it: both
// run in order on the world actor.
fn test_reach_is_judged_from_the_movement_just_handled() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}
	mut s := &NetworkSession{
		player:        player.new_player()
		hub:           hub
		runtime_id:    hub.allocate_runtime_id()
		spawned:       true
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}
	s.player.reset_position(types.Vector3{0.0, 0.0, 0.0})
	hub.add(s)
	worldrt.world_call[bool]('test', mut wr, fn [s] (mut tx worldrt.WorldTx) bool {
		register_player(mut tx, s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	reachable := types.BlockPosition{10, 0, 0}
	assert !s.within_place_reach(reachable)
	s.handle_world_packet(move_packet(types.Vector3{10.0, 0.0, 0.0}))!
	assert s.within_place_reach(reachable)
}

// move_packet is a movement report placing the player at pos.
fn move_packet(pos types.Vector3) &proto.MovePlayerPacket {
	mut p := &proto.MovePlayerPacket{}
	p.position[0] = pos.x
	p.position[1] = pos.y
	p.position[2] = pos.z
	return p
}
