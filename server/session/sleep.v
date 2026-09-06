module session

import bedrock_v.protocol.types
import server.block
import server.player
import server.world
import server.worldrt

// bed_block is the one block id every bed colour shares; the colour lives in
// the block entity rather than in the block itself.
const bed_block = 'minecraft:bed'

// bed_reach is how far a player may stand from a bed and still use it.
const bed_reach = f32(2.0)

// bed_standing_offsets are the blocks a respawning player is placed in,
// searched in this order.
const bed_standing_offsets = [
	types.BlockPosition{-1, 0, 0},
	types.BlockPosition{1, 0, 0},
	types.BlockPosition{0, 0, -1},
	types.BlockPosition{0, 0, 1},
	types.BlockPosition{-1, 0, -1},
	types.BlockPosition{-1, 0, 1},
	types.BlockPosition{1, 0, -1},
	types.BlockPosition{1, 0, 1},
	types.BlockPosition{0, 1, 0},
]

// is_bed reports whether a block runtime id is a bed.
fn is_bed(block_id int) bool {
	b := block.get(block_id) or { return false }
	return b.identifier() == bed_block
}

// use_bed is what right clicking a bed does: it becomes the player's spawn
// point and then the night skip is refused because sleeping itself doesn't
// exist yet. Vanilla sets the spawn before it decides whether the player may
// sleep, so a bed used at the wrong time still moves the spawn.
//
// Beds outside the overworld explode in vanilla. Explosions don't exist yet
// either, so the use is refused instead; the client already knows a bed there
// is not somewhere to sleep.
fn use_bed(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition) bool {
	if tx.wr.world.dimension.id != world.overworld.id {
		s.player.send_translation('%tile.bed.noSleep', [])
		return true
	}
	if !within_bed_reach(s.feet_position(), pos) {
		s.player.send_translation('%tile.bed.tooFar', [])
		return true
	}
	// A bed nobody can arrive beside is not a spawn point. Falling through
	// leaves the click to ordinary placement as vanilla does.
	bed_standing_spot(mut tx, pos) or {
		s.player.send_translation('%tile.bed.obstructed', [])
		return false
	}
	point := player.SpawnPoint{
		world: tx.wr.world.name
		pos:   pos
	}
	if s.player.spawn_point() or { player.SpawnPoint{} } != point {
		s.player.set_spawn_point(point)
		s.player.send_translation('%tile.bed.respawnSet', [])
	}
	s.player.send_translation('%tile.bed.noSleep', [])
	return true
}

fn within_bed_reach(feet types.Vector3, pos types.BlockPosition) bool {
	dx := feet.x - (f32(pos.x) + 0.5)
	dy := feet.y - (f32(pos.y) + 0.5)
	dz := feet.z - (f32(pos.z) + 0.5)
	return dx * dx + dy * dy + dz * dz <= bed_reach * bed_reach
}

// bed_standing_spot is where a player using or returning to the bed at pos is
// put: the first neighbouring block with a floor under it and room to stand.
// none means the bed is walled in which is what makes it unusable.
fn bed_standing_spot(mut tx worldrt.WorldTx, pos types.BlockPosition) ?types.Vector3 {
	for offset in bed_standing_offsets {
		x := pos.x + offset.x
		y := pos.y + offset.y
		z := pos.z + offset.z
		if !saved_floor_solid(block_at(tx, x, y - 1, z)) {
			continue
		}
		if !saved_body_clear(block_at(tx, x, y, z)) || !saved_body_clear(block_at(tx, x, y + 1, z)) {
			continue
		}
		return types.Vector3{f32(x) + 0.5, f32(y) + player_eye_height, f32(z) + 0.5}
	}
	return none
}

// respawn_position is where a player comes back: beside their own bed when it
// is still standing in this world with room to arrive and the world's spawn
// otherwise. The bed is looked up rather than remembered, so mining it out is
// enough to lose it.
fn respawn_position(mut tx worldrt.WorldTx, mut s NetworkSession) types.Vector3 {
	world_spawn := world_spawn_position(tx.wr.world, s.world_binding().generator)
	point := s.player.spawn_point() or { return world_spawn }
	if point.world != tx.wr.world.name {
		return world_spawn
	}
	if is_bed(block_at(tx, point.pos.x, point.pos.y, point.pos.z)) {
		if spot := bed_standing_spot(mut tx, point.pos) {
			return spot
		}
	}
	s.player.send_translation('%tile.bed.notValid', [])
	return world_spawn
}
