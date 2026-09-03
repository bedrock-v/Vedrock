module player

import bedrock_v.protocol.types

// spawn_point is where this player comes back after dying, or none when they
// have never set one and the world's own spawn still decides.
pub fn (p &Player) spawn_point() ?types.Vector3 {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	if !p.has_spawn_point {
		return none
	}
	return p.spawn_point
}

pub fn (mut p Player) set_spawn_point(pos types.Vector3) {
	p.state_mutex.lock()
	p.spawn_point = pos
	p.has_spawn_point = true
	p.state_mutex.unlock()
}

// clear_spawn_point sends the player back to the world spawn, as a bed that no
// longer exists does.
pub fn (mut p Player) clear_spawn_point() {
	p.state_mutex.lock()
	p.has_spawn_point = false
	p.spawn_point = types.Vector3{}
	p.state_mutex.unlock()
}
