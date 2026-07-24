module session

import os
import server.internal.gamedata

fn test_set_difficulty_persists_to_this_instances_own_file_only() {
	dir := os.join_path(os.temp_dir(), 'vedrock_difficulty_test')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}

	file1 := os.join_path(dir, 'srv1.yml')
	file2 := os.join_path(dir, 'srv2.yml')
	os.write_file(file1, 'difficulty: "normal"\n') or { panic(err) }
	os.write_file(file2, 'difficulty: "normal"\n') or { panic(err) }

	mut hub1 := new_hub(gamedata.GameData{})
	hub1.conf_file = file1

	hub1.set_difficulty(3)

	assert hub1.difficulty_value() == 3
	assert os.read_file(file1) or { '' }.contains('difficulty: "hard"')
	// srv2's own file must be completely untouched.
	assert os.read_file(file2) or { '' }.contains('difficulty: "normal"')
}
