module player

import bedrock_v.protocol.types

fn test_a_player_starts_without_a_spawn_point() {
	p := new_player()
	if _ := p.spawn_point() {
		assert false, 'a fresh player already had a spawn point'
	}
}

fn test_setting_and_clearing_a_spawn_point() {
	mut p := new_player()
	p.set_spawn_point(types.Vector3{1.5, 64.0, -2.5})
	point := p.spawn_point() or {
		assert false, 'spawn point was not recorded'
		return
	}
	assert point.x == 1.5
	assert point.y == 64.0
	assert point.z == -2.5

	p.clear_spawn_point()
	if _ := p.spawn_point() {
		assert false, 'spawn point survived being cleared'
	}
}
