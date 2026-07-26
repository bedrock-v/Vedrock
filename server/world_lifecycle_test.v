module server

import os
import server.conf
import server.world

fn world_lifecycle_test_server(dir string) &Server {
	cfg := conf.Config{
		port:                    19134
		worlds_dir:              os.join_path(dir, 'worlds')
		players_dir:             os.join_path(dir, 'players')
		crashdumps_dir:          os.join_path(dir, 'crashdumps')
		ops_file:                os.join_path(dir, 'ops.txt')
		permissions_file:        os.join_path(dir, 'permissions.yml')
		player_permissions_file: os.join_path(dir, 'player_permissions.yml')
		whitelist_file:          os.join_path(dir, 'whitelist.txt')
	}
	return new(settings: cfg) or { panic('server failed to start: ${err}') }
}

fn test_world_reports_the_boot_loaded_default_world() {
	dir := os.join_path(os.temp_dir(), 'vedrock_world_lifecycle_default_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	mut srv := world_lifecycle_test_server(dir)

	handle := srv.world('world') or { panic('expected default world handle: ${err}') }
	assert handle.name() == 'world'

	names := srv.worlds().map(it.name())
	assert 'world' in names
}

fn test_world_returns_an_error_for_an_unloaded_name() {
	dir := os.join_path(os.temp_dir(), 'vedrock_world_lifecycle_missing_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	mut srv := world_lifecycle_test_server(dir)

	if _ := srv.world('does-not-exist') {
		assert false
	}
}

fn test_load_world_creates_a_new_world_and_is_idempotent() {
	dir := os.join_path(os.temp_dir(), 'vedrock_world_lifecycle_create_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	mut srv := world_lifecycle_test_server(dir)

	first := srv.load_world(name: 'creative', dimension: world.overworld, generator_name: 'flat') or {
		panic('expected world to be created: ${err}')
	}
	assert first.name() == 'creative'
	assert os.is_dir(os.join_path(dir, 'worlds', 'creative'))

	second := srv.load_world(name: 'creative') or {
		panic('expected idempotent load_world to succeed: ${err}')
	}
	assert second.name() == 'creative'

	names := srv.worlds().map(it.name())
	assert 'creative' in names
}

fn test_load_world_reopens_an_unloaded_world_from_disk() {
	dir := os.join_path(os.temp_dir(), 'vedrock_world_lifecycle_reopen_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	mut srv := world_lifecycle_test_server(dir)

	srv.load_world(name: 'lobby', dimension: world.overworld, generator_name: 'flat') or {
		panic('expected world to be created: ${err}')
	}
	srv.unload_world('lobby') or { panic('expected unload to succeed: ${err}') }

	if _ := srv.world('lobby') {
		assert false
	}

	reopened := srv.load_world(name: 'lobby') or {
		panic('expected load_world to reopen the world from disk: ${err}')
	}
	assert reopened.name() == 'lobby'
}

fn test_unload_world_removes_it_from_worlds_and_world() {
	dir := os.join_path(os.temp_dir(), 'vedrock_world_lifecycle_unload_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	mut srv := world_lifecycle_test_server(dir)

	srv.load_world(name: 'scratch') or { panic('expected world to be created: ${err}') }
	srv.unload_world('scratch') or { panic('expected unload to succeed: ${err}') }

	if _ := srv.world('scratch') {
		assert false
	}
	names := srv.worlds().map(it.name())
	assert 'scratch' !in names
}

fn test_unload_world_refuses_the_default_world() {
	dir := os.join_path(os.temp_dir(), 'vedrock_world_lifecycle_default_refuse_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	mut srv := world_lifecycle_test_server(dir)

	if _ := srv.unload_world('world') {
		assert false
	} else {
		assert err.msg().contains('default world')
	}
}
