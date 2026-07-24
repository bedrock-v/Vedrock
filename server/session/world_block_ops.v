module session

import protocol
import protocol.types
import server.world

// block_at returns this transaction's authoritative block ID, preferring a
// stored override and falling back to generation. It always reads from the
// WorldRuntime bound to the transaction, not from the acting session.
fn (tx &WorldTx) block_at(x int, y int, z int) int {
	if id := tx.wr.world.block_override(x, y, z) {
		return id
	}
	gen := tx.wr.world.make_generator(tx.wr.hub.build_generator(tx.wr.world))
	return gen.block_at(x, y, z)
}

fn (tx &WorldTx) neighbor_ids(pos types.BlockPosition) world.NeighborBlockIDs {
	return world.NeighborBlockIDs{
		north: tx.block_at(pos.x, pos.y, pos.z - 1)
		east:  tx.block_at(pos.x + 1, pos.y, pos.z)
		south: tx.block_at(pos.x, pos.y, pos.z + 1)
		west:  tx.block_at(pos.x - 1, pos.y, pos.z)
		above: tx.block_at(pos.x, pos.y + 1, pos.z)
		below: tx.block_at(pos.x, pos.y - 1, pos.z)
	}
}

// recompute_neighbor_blocks updates the connected block state at pos and its
// horizontal neighbors using this transaction's world view. It is safe to call
// from within an already running WorldTx task.
fn (mut tx WorldTx) recompute_neighbor_blocks(pos types.BlockPosition) {
	if isnil(tx.wr.hub.palette) {
		return
	}
	for p in [
		pos,
		face_offset(pos, 2),
		face_offset(pos, 3),
		face_offset(pos, 4),
		face_offset(pos, 5),
	] {
		old_id := tx.block_at(p.x, p.y, p.z)
		if old_id == world.air.network_id {
			continue
		}
		new_id := tx.wr.hub.palette.connected_block(old_id, tx.neighbor_ids(p))
		if new_id != old_id {
			tx.set_block(p.x, p.y, p.z, new_id)
		}
	}
}

// broadcast_swing sends the acting session's arm swing animation to every
// other session in this transaction's world.
fn (mut tx WorldTx) broadcast_swing(s &NetworkSession) {
	tx.wr.broadcast_world_except(s.runtime_id, &protocol.AnimatePacket{
		action:           protocol.animate_action_swing_arm
		actor_runtime_id: s.runtime_id
	})
}

// broadcast_destroy_particles sends the block break particle effect to every
// session in this transaction's world.
fn (mut tx WorldTx) broadcast_destroy_particles(x int, y int, z int, runtime_id int) {
	tx.wr.broadcast_world(&protocol.LevelEventPacket{
		event_id:   protocol.level_event_particles_destroy_block
		position:   types.Vector3{f32(x) + 0.5, f32(y) + 0.5, f32(z) + 0.5}
		event_data: runtime_id
	})
}

// notify_block_changed re-evaluates liquid flow and connected block state
// (walls, fence gates, etc.) at pos after a mutation, mirroring the old
// session level after_block_changed.
fn (mut tx WorldTx) notify_block_changed(pos types.BlockPosition) {
	tx.on_block_changed(pos.x, pos.y, pos.z)
	tx.recompute_neighbor_blocks(pos)
}
