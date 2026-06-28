module storage

import os
import json

pub struct InvItem {
pub mut:
	id               int
	meta             int
	count            int
	block_runtime_id int
}

pub struct PlayerData {
pub mut:
	x        f32
	y        f32
	z        f32
	yaw      f32
	pitch    f32
	gamemode int
	items    []InvItem
}

fn player_path(dir string, key string) string {
	return os.join_path(dir, '${key}.json')
}

pub fn load_player(dir string, key string) ?PlayerData {
	path := player_path(dir, key)
	if !os.exists(path) {
		return none
	}
	text := os.read_file(path) or { return none }
	return json.decode(PlayerData, text) or { return none }
}

pub fn save_player(dir string, key string, data PlayerData) ! {
	os.mkdir_all(dir)!
	os.write_file(player_path(dir, key), json.encode(data))!
}
