module conf

import os

fn test_toml_config_round_trips_every_setting() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_conf_toml_${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'vedrock.toml')

	// A missing file is written with the defaults and reads back unchanged.
	written := load_from(path) or {
		assert false, '${err}'
		return
	}
	assert os.exists(path)
	reloaded := load_from(path) or {
		assert false, '${err}'
		return
	}
	assert reloaded == written

	mut custom := Config{
		motd:                    'Custom'
		sub_motd:                'Sub'
		max_players:             7
		gamemode:                'creative'
		difficulty:              'hard'
		language:                'tr'
		debug:                   true
		address:                 '127.0.0.1'
		port:                    25565
		view_distance:           12
		xbox_auth:               false
		encryption:              true
		compression_threshold:   512
		generator:               'normal'
		default_world:           'lobby'
		load_all_worlds:         true
		resource_packs:          false
		resource_packs_dir:      'packs'
		force_resource_packs:    true
		allow_client_packs:      false
		cdn_packs:               'a,1,b,2'
		worlds_dir:              'w'
		players_dir:             'p'
		crashdumps_dir:          'c'
		ops_file:                'o.txt'
		permissions_file:        'perm.yml'
		player_permissions_file: 'pp.yml'
		whitelist_file:          'wl.txt'
		config_file:             path
	}
	write_default(path, custom) or {
		assert false, '${err}'
		return
	}
	got := load_from(path) or {
		assert false, '${err}'
		return
	}
	assert got == custom
}

fn test_difficulty_update_rewrites_the_toml_key() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_conf_diff_${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'vedrock.toml')
	load_from(path) or {
		assert false, '${err}'
		return
	}
	update_difficulty_in_file(path, 'hard') or {
		assert false, '${err}'
		return
	}
	reloaded := load_from(path) or {
		assert false, '${err}'
		return
	}
	assert reloaded.difficulty == 'hard'
}
