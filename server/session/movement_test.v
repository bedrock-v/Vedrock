module session

import bedrock_v.protocol.current as proto
import bedrock_v.protocol.types
import server.internal.gamedata
import server.internal.logger
import server.player
import server.world
import server.world.db
import server.worldrt

fn movement_test_session(mut hub Hub, mut wr worldrt.WorldRuntime) &NetworkSession {
	mut s := &NetworkSession{
		player:        player.new_player()
		hub:           hub
		runtime_id:    hub.allocate_runtime_id()
		spawned:       true
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}
	hub.add(s)
	worldrt.world_call[bool]('test', mut wr, fn [s] (mut tx worldrt.WorldTx) bool {
		register_player(mut tx, s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn test_movement_before_spawn_is_dropped_not_stranded() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut s := &NetworkSession{
		player:        player.new_player()
		hub:           hub
		runtime_id:    1
		spawned:       false
		world:         wr.world
		world_runtime: wr
		log:           logger.new(.info)
	}

	s.handle_world_packet(move_packet(types.Vector3{9.0, 9.0, 9.0}))!
	assert s.movement_scheduled == false
	assert s.pending_movement == none
	assert wr.metrics().queued_tasks == 0
	assert s.player.position() != types.Vector3{9.0, 9.0, 9.0}

	s.spawned = true
	hub.add(s)
	worldrt.world_call[bool]('test', mut wr, fn [s] (mut tx worldrt.WorldTx) bool {
		register_player(mut tx, s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	want := types.Vector3{10.0, 11.0, 12.0}
	s.handle_world_packet(move_packet(want))!
	assert s.player.position() == want
}

// update_movement returns early while movement_scheduled is set. A flag left
// behind by one report would silently freeze the player for every report after.
fn test_movement_scheduled_flag_clears_after_every_report() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	mut s := movement_test_session(mut hub, mut wr)

	for i in 0 .. 500 {
		pos := types.Vector3{f32(i), 0.0, 0.0}
		s.handle_world_packet(move_packet(pos))!
		assert s.movement_scheduled == false
		assert s.player.position() == pos
	}
}

// move_packet is a movement report placing the player at pos.
fn move_packet(pos types.Vector3) &proto.MovePlayerPacket {
	mut p := &proto.MovePlayerPacket{}
	p.position[0] = pos.x
	p.position[1] = pos.y
	p.position[2] = pos.z
	return p
}
