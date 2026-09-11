module session

import os
import bedrock_v.protocol.types
import server.conf
import server.internal.auth
import server.internal.gamedata
import server.internal.logger
import server.player
import server.player.playerdb
import server.world
import server.world.db

// resume_hub has two worlds. The first added is the default, so 'arena' is
// only ever reached by a save that names it.
fn resume_hub(dir string) &Hub {
	mut hub := new_hub(gamedata.GameData{},
		player_data_provider: playerdb.FileProvider{
			dir: dir
		}
	)
	hub.add_world(db.new_world('world', none, 'flat', world.overworld))
	hub.add_world(db.new_world('arena', none, 'flat', world.overworld))
	return hub
}

fn resume_session(mut hub Hub, name string) &NetworkSession {
	mut wr := hub.default_world_runtime() or { panic('expected a default world') }
	target := wr.world
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: name
	}
	mut s := &NetworkSession{
		player:        pl
		hub:           hub
		world:         target
		world_runtime: wr
		generator:     target.make_generator(hub.build_generator(target))
		runtime_id:    hub.allocate_runtime_id()
		conn:          &Conn{
			transport: &FakeTransport{}
		}
		cfg:           conf.Config{}
		log:           logger.new(.info)
	}
	return s
}

// standing_position is somewhere the flat generator agrees a player can be,
// a rejected saved position is rejected for the world it names rather than for
// being unsafe.
fn standing_position(mut hub Hub) types.Vector3 {
	mut wr := hub.default_world_runtime() or { panic('expected a default world') }
	target := wr.world
	gen := target.make_generator(hub.build_generator(target))
	return types.Vector3{18.5, f32(gen.spawn_point().y) + player_eye_height, -6.5}
}

fn resume_dir(tag string) string {
	return os.join_path(os.vtmp_dir(), 'vedrock_player_world_${tag}_${os.getpid()}')
}

fn test_a_player_comes_back_in_the_world_they_left() {
	dir := resume_dir('resume')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut hub := resume_hub(dir)
	defer {
		hub.close_worlds()
	}
	saved := standing_position(mut hub)
	playerdb.save_player(dir, 'Alex', playerdb.PlayerData{
		world: 'arena'
		x:     saved.x
		y:     saved.y
		z:     saved.z
	})!

	mut s := resume_session(mut hub, 'Alex')
	state := s.resolve_spawn_state()!

	assert s.world_name() == 'arena'
	assert state.pos == saved
}

fn test_coords_from_missing_world_are_not_used_in_default() {
	dir := resume_dir('missing')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut hub := resume_hub(dir)
	defer {
		hub.close_worlds()
	}
	saved := standing_position(mut hub)
	playerdb.save_player(dir, 'Alex', playerdb.PlayerData{
		world: 'deleted-arena'
		x:     saved.x
		y:     saved.y
		z:     saved.z
	})!

	mut s := resume_session(mut hub, 'Alex')
	state := s.resolve_spawn_state()!

	assert s.world_name() == 'world'
	assert state.pos != saved
	assert state.pos.x == 0.0
	assert state.pos.z == 0.0
}

fn test_save_without_a_world_still_restores_its_pos() {
	dir := resume_dir('legacy')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut hub := resume_hub(dir)
	defer {
		hub.close_worlds()
	}
	saved := standing_position(mut hub)
	playerdb.save_player(dir, 'Alex', playerdb.PlayerData{
		x: saved.x
		y: saved.y
		z: saved.z
	})!

	mut s := resume_session(mut hub, 'Alex')
	state := s.resolve_spawn_state()!

	assert s.world_name() == 'world'
	assert state.pos == saved
}

fn test_saving_records_the_world_the_player_is_in() {
	dir := resume_dir('save')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut hub := resume_hub(dir)
	defer {
		hub.close_worlds()
	}
	mut s := resume_session(mut hub, 'Alex')
	mut arena := hub.world_runtime('arena') or { panic('expected an arena runtime') }
	s.set_world_binding(arena, arena.world.make_generator(hub.build_generator(arena.world)))

	s.save_player_data()

	data := playerdb.load_player(dir, 'Alex') or {
		panic('nothing was saved for Alex')
	}
	assert data.world == 'arena'
}
