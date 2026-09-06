module player

import bedrock_v.protocol.types

// SpawnPoint is the bed a player comes back to. The world is part of it
// because the same coordinates name a different place in every other world,
// and an empty world name is a player who has never used a bed.
pub struct SpawnPoint {
pub:
	world string
	pos   types.BlockPosition
}

// spawn_point is the bed this player last used or none while the world's own
// spawn still decides where they come back.
pub fn (p &Player) spawn_point() ?SpawnPoint {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	if p.spawn_point.world == '' {
		return none
	}
	return p.spawn_point
}

pub fn (mut p Player) set_spawn_point(point SpawnPoint) {
	p.state_mutex.lock()
	p.spawn_point = point
	p.state_mutex.unlock()
}
