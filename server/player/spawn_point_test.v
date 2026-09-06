module player

import bedrock_v.protocol.types

fn test_a_player_starts_without_a_spawn_point() {
	p := new_player()
	if _ := p.spawn_point() {
		assert false, 'a fresh player already had a spawn point'
	}
}

fn test_a_spawn_point_keeps_the_world_it_was_set_in() {
	mut p := new_player()
	p.set_spawn_point(SpawnPoint{
		world: 'arena'
		pos:   types.BlockPosition{1, 64, -2}
	})
	point := p.spawn_point() or {
		assert false, 'spawn point was not recorded'
		return
	}
	assert point.world == 'arena'
	assert point.pos == types.BlockPosition{1, 64, -2}
}
