module session

import bedrock_v.protocol.types
import server.world
import server.world.particle
import server.world.sound
import bedrock_v.protocol.current as proto

// block_at returns this transaction's authoritative block ID, preferring a
// stored override and falling back to generation. It always reads from the
// WorldRuntime bound to the transaction, not from the acting session.
fn block_at(tx &WorldTx, x int, y int, z int) int {
	if id := tx.wr.world.block_override(x, y, z) {
		return id
	}
	mut wr := tx.wr
	return wr.generated_block(x, y, z)
}

fn neighbor_ids(tx &WorldTx, pos types.BlockPosition) world.NeighborBlockIDs {
	return world.NeighborBlockIDs{
		north: block_at(tx, pos.x, pos.y, pos.z - 1)
		east:  block_at(tx, pos.x + 1, pos.y, pos.z)
		south: block_at(tx, pos.x, pos.y, pos.z + 1)
		west:  block_at(tx, pos.x - 1, pos.y, pos.z)
		above: block_at(tx, pos.x, pos.y + 1, pos.z)
		below: block_at(tx, pos.x, pos.y - 1, pos.z)
	}
}

// recompute_neighbor_blocks updates the connected block state at pos and its
// horizontal neighbors using this transaction's world view. It is safe to call
// from within an already running WorldTx task.
fn recompute_neighbor_blocks(mut tx WorldTx, pos types.BlockPosition) {
	if isnil(tx.wr.game.hub.palette) {
		return
	}
	for p in [
		pos,
		face_offset(pos, 2),
		face_offset(pos, 3),
		face_offset(pos, 4),
		face_offset(pos, 5),
	] {
		old_id := block_at(tx, p.x, p.y, p.z)
		if old_id == world.air.network_id {
			continue
		}
		new_id := tx.wr.game.hub.palette.connected_block(old_id, neighbor_ids(tx, p))
		if new_id != old_id {
			tx.set_block(p.x, p.y, p.z, new_id)
		}
	}
}

// broadcast_swing sends the acting session's arm swing animation to every
// other session in this transaction's world.
fn broadcast_swing(mut tx WorldTx, s &NetworkSession) {
	tx.wr.broadcast_world_except(s.runtime_id, &proto.AnimatePacket{
		action:            proto.AnimatePacketAction.swing
		target_runtime_id: proto.actor_runtime_id(s.runtime_id)
	})
}

// broadcast_destroy_particles sends the block break particle effect to every
// session in this transaction's world.
fn broadcast_destroy_particles(mut tx WorldTx, x int, y int, z int, runtime_id int) {
	add_particle(mut tx, types.Vector3{
		x: f32(x) + 0.5
		y: f32(y) + 0.5
		z: f32(z) + 0.5
	}, particle.BlockBreak{
		block_runtime_id: runtime_id
	})
}

// broadcast_cracking sends one block cracking level event to every session in
// this transaction's world. The start, update and stop events differ only in
// their id and payload, so they all go through here.
fn broadcast_cracking(mut tx WorldTx, event_id int, pos types.BlockPosition, data int) {
	mut packet := &proto.LevelEventPacket{
		event_id: event_id
		data:     data
	}
	packet.position[0] = f32(pos.x)
	packet.position[1] = f32(pos.y)
	packet.position[2] = f32(pos.z)
	tx.wr.broadcast_world(packet)
}

// broadcast_crack_speed updates the crack animation speed for a block that is
// already being mined, for every session in this transaction's world.
fn broadcast_crack_speed(mut tx WorldTx, pos types.BlockPosition, data int) {
	broadcast_cracking(mut tx, proto.level_event_update_block_cracking, pos, data)
}

// broadcast_punch_particle sends the periodic mining particle for the face
// being hit, to every session in this transaction's world.
fn broadcast_punch_particle(mut tx WorldTx, pos types.BlockPosition, runtime_id int, face int) {
	add_particle(mut tx, types.Vector3{
		x: f32(pos.x)
		y: f32(pos.y)
		z: f32(pos.z)
	}, particle.PunchBlock{
		block_runtime_id: runtime_id
		face:             face
	})
}

fn broadcast_stop_cracking(mut tx WorldTx, x int, y int, z int) {
	broadcast_cracking(mut tx, proto.level_event_stop_block_cracking, types.BlockPosition{x, y, z}, 0)
}

// broadcast_place_sound sends the block placement sound to every session in
// this transaction's world.
fn broadcast_place_sound(mut tx WorldTx, s &NetworkSession, x int, y int, z int, runtime_id int) {
	snd := sound.BlockPlace{
		block_runtime_id: runtime_id
	}
	tx.wr.broadcast_world(proto.level_sound_event(snd.event_name(), types.Vector3{
		x: f32(x) + 0.5
		y: f32(y) + 0.5
		z: f32(z) + 0.5
	}, snd.data(), 'minecraft:player', s.runtime_id))
}

// notify_block_changed re-evaluates liquid flow and connected block state
// (walls, fence gates, etc.) at pos after a mutation, mirroring the old
// session level after_block_changed.
fn notify_block_changed(mut tx WorldTx, pos types.BlockPosition) {
	tx.on_block_changed(pos.x, pos.y, pos.z)
	recompute_neighbor_blocks(mut tx, pos)
}
