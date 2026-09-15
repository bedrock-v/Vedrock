module playerdb

import os
import json2

pub struct InvItem {
pub mut:
	slot             int = -1
	id               int
	meta             int
	count            int
	block_runtime_id int
	raw_extra_data   []u8
}

pub struct PlayerData {
pub mut:
	x              f32
	y              f32
	z              f32
	yaw            f32
	pitch          f32
	gamemode       int
	items          []InvItem
	has_last_death bool
	last_death_x   f32
	last_death_y   f32
	last_death_z   f32
}

// safe_key strips anything that could let a key (which may come from an
// unauthenticated display name) escape dir - path separators, drive colons and
// parent-dir dots. The result is always a plain file stem inside dir.
fn safe_key(key string) string {
	mut out := []u8{cap: key.len}
	for c in key.bytes() {
		if c == `/` || c == `\\` || c == `:` || c == 0 {
			out << `_`
		} else {
			out << c
		}
	}
	mut cleaned := out.bytestr().replace('..', '_')
	cleaned = cleaned.trim_left('.')
	if cleaned == '' {
		return 'unknown'
	}
	return cleaned
}

fn player_path(dir string, key string) string {
	return os.join_path(dir, '${safe_key(key)}.json')
}

pub fn load_player(dir string, key string) ?PlayerData {
	path := player_path(dir, key)
	if !os.exists(path) {
		return none
	}
	text := os.read_file(path) or { return none }
	return json2.decode[PlayerData](text) or { return none }
}

// save_player writes player data atomically - the JSON goes to a temp file
// first, then a rename swaps it over the target. A crash mid-write can only
// ever leave a stale but valid save behind, never a truncated one.
pub fn save_player(dir string, key string, data PlayerData) ! {
	os.mkdir_all(dir)!
	path := player_path(dir, key)
	tmp := '${path}.tmp.${os.getpid()}'
	os.write_file(tmp, json2.encode(data, escape_unicode: true)) or {
		os.rm(tmp) or {}
		return err
	}
	os.rename(tmp, path) or {
		os.rm(tmp) or {}
		return err
	}
}
