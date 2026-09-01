module player

import bedrock_v.protocol.current as proto
import bedrock_v.protocol.types
import server.worldrt

// The player's own actions. Each one takes the transaction for the world the
// player is in which is both how it reaches the world and the proof that it
// is running on that world's actor: a transaction only exists inside a task.
//
// A verb speaks to its own client through the sink and to everyone else
// through the transaction. Both are built from the same state in the same
// actor turn and cannot disagree.

// teleport moves the player to pos, tells its own client to snap there and
// shows the move to everyone else in the world.
pub fn (mut p Player) teleport(mut tx worldrt.WorldTx, pos types.Vector3) {
	p.reset_position(pos)
	current := p.movement()
	mut sink := p.sink
	rid := sink.runtime_id()

	mut move_packet := &proto.MovePlayerPacket{
		player_runtime_id: proto.actor_runtime_id(rid)
		y_head_rotation:   current.head_yaw
		position_mode:     proto.PlayerPositionMode.teleport
		teleport_data:     proto.MovePlayerTeleportData{}
		on_ground:         false
	}
	move_packet.position[0] = current.position.x
	move_packet.position[1] = current.position.y
	move_packet.position[2] = current.position.z
	move_packet.rotation[0] = current.pitch
	move_packet.rotation[1] = current.yaw
	sink.deliver(move_packet)
	sink.expect_teleport_ack(current.position)

	tx.wr.broadcast_world_except(rid, p.move_actor_packet())
}

// move_actor_packet is this player's position as other clients see it.
pub fn (p &Player) move_actor_packet() &proto.MoveActorAbsolutePacket {
	current := p.movement()
	mut sink := p.sink
	return &proto.MoveActorAbsolutePacket{
		move_data: proto.MoveActorAbsoluteData{
			actor_runtime_id: proto.actor_runtime_id(sink.runtime_id())
			header:           i8(proto.move_actor_flag_on_ground)
			position_x:       current.position.x
			position_y:       current.position.y
			position_z:       current.position.z
			rotation_x:       proto.rotation_byte(current.pitch)
			rotation_y:       proto.rotation_byte(current.yaw)
			rotation_y_head:  proto.rotation_byte(current.head_yaw)
		}
	}
}
