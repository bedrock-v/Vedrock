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

// forget_spawn_point_in drops this player's spawn point when it belongs to the
// named world for when that world is deleted. The test and the clear are one
// operation because the player may be binding a new bed on another thread.
pub fn (mut p Player) forget_spawn_point_in(world string) {
	p.state_mutex.lock()
	if p.spawn_point.world == world {
		p.spawn_point = SpawnPoint{}
	}
	p.state_mutex.unlock()
}

pub fn (mut p Player) set_spawn_point(point SpawnPoint) {
	p.state_mutex.lock()
	p.spawn_point = point
	p.state_mutex.unlock()
}
