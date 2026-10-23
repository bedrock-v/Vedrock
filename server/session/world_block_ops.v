module session

import bedrock_v.nbt
import server.entity
import bedrock_v.protocol.types
import server.world
import server.world.particle
import server.world.sound
import bedrock_v.protocol.current as proto
import server.worldrt

// block_at returns this transaction's authoritative block ID, preferring a
// stored override and falling back to generation. It always reads from the
// worldrt.WorldRuntime bound to the transaction, not from the acting session.
fn block_at(tx &worldrt.WorldTx, x int, y int, z int) int {
	if id := tx.wr.world.block_override(x, y, z) {
		return id
	}
	mut wr := tx.wr
	return wr.generated_block(x, y, z)
}

fn neighbor_ids(tx &worldrt.WorldTx, pos types.BlockPosition) world.NeighborBlockIDs {
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
// from within an already running worldrt.WorldTx task.
fn recompute_neighbor_blocks(mut tx worldrt.WorldTx, pos types.BlockPosition) {
	if isnil(tx.wr.services.block_palette()) {
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
		new_id := tx.wr.services.block_palette().connected_block(old_id, neighbor_ids(tx, p))
		if new_id != old_id {
			tx.set_block(p.x, p.y, p.z, new_id)
		}
	}
}

// broadcast_swing sends the acting session's arm swing animation to every
// other session in this transaction's world.
fn broadcast_swing(mut tx worldrt.WorldTx, s &NetworkSession) {
	for mut v in viewers_except(mut tx, s.runtime_id) {
		v.view_actor_swing(s.runtime_id)
	}
}

// broadcast_destroy_particles sends the block break particle effect to every
// session in this transaction's world.
fn broadcast_destroy_particles(mut tx worldrt.WorldTx, x int, y int, z int, runtime_id int) {
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
fn broadcast_cracking(mut tx worldrt.WorldTx, event_id int, pos types.BlockPosition, data int) {
	add_particle(mut tx, types.Vector3{
		x: f32(pos.x)
		y: f32(pos.y)
		z: f32(pos.z)
	}, particle.Custom{
		id:      event_id
		payload: data
	})
}

// broadcast_block_entity tells every session in this transaction's world about
// the data attached to a block. Vedrock keeps that data beside the block rather
// than inside its runtime id, so it travels on its own rather than riding along
// with the block change.
fn broadcast_block_entity(mut tx worldrt.WorldTx, pos types.BlockPosition, tags nbt.RootTag) {
	for mut v in tx.wr.viewers() {
		v.view_block_entity(pos, tags)
	}
}

// broadcast_crack_speed updates the crack animation speed for a block that is
// already being mined, for every session in this transaction's world.
fn broadcast_crack_speed(mut tx worldrt.WorldTx, pos types.BlockPosition, data int) {
	broadcast_cracking(mut tx, proto.level_event_update_block_cracking, pos, data)
}

// broadcast_punch_particle sends the periodic mining particle for the face
// being hit, to every session in this transaction's world.
fn broadcast_punch_particle(mut tx worldrt.WorldTx, pos types.BlockPosition, runtime_id int, face int) {
	add_particle(mut tx, types.Vector3{
		x: f32(pos.x)
		y: f32(pos.y)
		z: f32(pos.z)
	}, particle.PunchBlock{
		block_runtime_id: runtime_id
		face:             face
	})
}

fn broadcast_stop_cracking(mut tx worldrt.WorldTx, x int, y int, z int) {
	broadcast_cracking(mut tx, proto.level_event_stop_block_cracking, types.BlockPosition{x, y, z}, 0)
}

// broadcast_place_sound sends the block placement sound to every session in
// this transaction's world.
fn broadcast_place_sound(mut tx worldrt.WorldTx, s &NetworkSession, x int, y int, z int, runtime_id int) {
	snd := sound.BlockPlace{
		block_runtime_id: runtime_id
	}
	play_actor_sound(mut tx, types.Vector3{
		x: f32(x) + 0.5
		y: f32(y) + 0.5
		z: f32(z) + 0.5
	}, snd, entity.SoundSource{
		actor:      s.runtime_id
		identifier: player_actor_identifier
	})
}

// notify_block_changed re-evaluates liquid flow and connected block state
// (walls, fence gates, etc.) at pos after a mutation, mirroring the old
// session level after_block_changed.
fn notify_block_changed(mut tx worldrt.WorldTx, pos types.BlockPosition) {
	tx.on_block_changed(pos.x, pos.y, pos.z)
	recompute_neighbor_blocks(mut tx, pos)
}
