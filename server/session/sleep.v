module session

import bedrock_v.protocol.types
import server.block
import server.world
import server.worldrt

// bed_block is the one block id every bed colour shares; the colour lives in
// the block entity rather than in the block itself.
const bed_block = 'minecraft:bed'

// is_bed reports whether a block runtime id is a bed.
fn is_bed(block_id int) bool {
	b := block.get(block_id) or { return false }
	return b.identifier() == bed_block
}

// use_bed is what right clicking a bed does: it becomes the player's spawn
// point. Beds do not work outside the overworld, which the client already
// knows, so the attempt is refused rather than silently accepted.
fn use_bed(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition) bool {
	if tx.wr.world.dimension.id != world.overworld.id {
		s.player.send_translation('%tile.bed.noSleep', [])
		return true
	}
	bed_side := types.Vector3{f32(pos.x) + 0.5, f32(pos.y) + 1.0, f32(pos.z) + 0.5}
	s.player.set_spawn_point(bed_side)
	s.player.send_translation('%tile.bed.respawnSet', [])
	return true
}

// respawn_position is where a player comes back: their own spawn point when
// they have one that is still somewhere they can stand, and the world's spawn
// otherwise. A bed that has since been mined into is not a place to arrive.
fn (s &NetworkSession) respawn_position() types.Vector3 {
	world_spawn := types.Vector3{0.0, f32(s.generator.spawn_y()) + player_eye_height, 0.0}
	own := s.player.spawn_point() or { return world_spawn }
	position := types.Vector3{own.x, own.y + player_eye_height, own.z}
	if !safe_player_position_in_world(s.world, s.generator, position) {
		return world_spawn
	}
	return position
}

// PlayerSpawnPointTask sets a player's spawn point on their own world runtime,
// since the caller may be another player's session thread or the console.
struct PlayerSpawnPointTask {
	runtime_id u64
	epoch      i64
	pos        types.Vector3
}

fn (t PlayerSpawnPointTask) name() string {
	return 'PlayerSpawnPointTask'
}

fn (t PlayerSpawnPointTask) run(mut tx worldrt.WorldTx) {
	mut target := player_for_epoch(mut tx, t.runtime_id, t.epoch) or { return }
	target.player.set_spawn_point(t.pos)
}

// set_spawn_point is the View entry point for moving where this player comes
// back after dying.
pub fn (mut s NetworkSession) set_spawn_point(x f32, y f32, z f32) {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	wr.submit(PlayerSpawnPointTask{
		runtime_id: s.runtime_id
		epoch:      s.world_binding().epoch
		pos:        types.Vector3{x, y, z}
	})
}
