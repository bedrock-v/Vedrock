module server

import os
import server.conf

// This proves the actual multi instance vision: two server.new() calls
// in the same process, given distinct paths, never touch the same ondisk
// state and end up with completely independent Hub instances. Each Config
// here uses its own worlds_dir/ops_file/etc rather than the shared defaults,
// which is exactly what Vedrockv003(aka 03) is expected to do.
fn test_servers_spawn_w_fully_isolated_state() {
	dir := os.join_path(os.temp_dir(), 'vedrock_multi_instance_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(os.join_path(dir, 'srv1')) or { panic(err) }
	os.mkdir_all(os.join_path(dir, 'srv2')) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}

	cfg1 := conf.Config{
		port:                    19132
		worlds_dir:              os.join_path(dir, 'srv1', 'worlds')
		players_dir:             os.join_path(dir, 'srv1', 'players')
		crashdumps_dir:          os.join_path(dir, 'srv1', 'crashdumps')
		ops_file:                os.join_path(dir, 'srv1', 'ops.txt')
		permissions_file:        os.join_path(dir, 'srv1', 'permissions.yml')
		player_permissions_file: os.join_path(dir, 'srv1', 'player_permissions.yml')
		whitelist_file:          os.join_path(dir, 'srv1', 'whitelist.txt')
	}
	cfg2 := conf.Config{
		port:                    19133
		worlds_dir:              os.join_path(dir, 'srv2', 'worlds')
		players_dir:             os.join_path(dir, 'srv2', 'players')
		crashdumps_dir:          os.join_path(dir, 'srv2', 'crashdumps')
		ops_file:                os.join_path(dir, 'srv2', 'ops.txt')
		permissions_file:        os.join_path(dir, 'srv2', 'permissions.yml')
		player_permissions_file: os.join_path(dir, 'srv2', 'player_permissions.yml')
		whitelist_file:          os.join_path(dir, 'srv2', 'whitelist.txt')
	}

	mut srv1 := new(settings: cfg1) or { panic('srv1 failed to start: ${err}') }
	mut srv2 := new(settings: cfg2) or { panic('srv2 failed to start: ${err}') }

	// Mutating one instance's ops list must never touch the other's.
	srv1.hub.ops.add('alex') or { panic('failed to add op: ${err}') }
	assert srv1.hub.ops.is_op('alex')
	assert !srv2.hub.ops.is_op('alex')

	assert os.is_dir(os.join_path(dir, 'srv1', 'worlds'))
	assert os.is_dir(os.join_path(dir, 'srv2', 'worlds'))
}
