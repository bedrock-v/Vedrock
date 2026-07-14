module db

import os

fn temp_worlds_dir() string {
	dir := os.join_path(os.temp_dir(), 'vedrock_worlds_test_${os.getpid()}_${rand_suffix()}')
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

fn rand_suffix() string {
	return os.getpid().str() + os.args.len.str()
}

fn make_world_on_disk(worlds_dir string, name string) {
	os.mkdir_all(os.join_path(worlds_dir, name, 'db')) or { panic(err) }
}

fn test_delete_refuses_path_traversal() {
	worlds_dir := temp_worlds_dir()
	defer {
		os.rmdir_all(worlds_dir) or {}
	}
	// A sibling dir we must never be able to reach out and delete.
	victim := os.join_path(os.dir(worlds_dir), 'vedrock_victim_${os.getpid()}')
	os.mkdir_all(victim) or { panic(err) }
	defer {
		os.rmdir_all(victim) or {}
	}

	for bad in ['../vedrock_victim_${os.getpid()}', '..', 'a/b', '/etc', 'foo/../bar'] {
		if _ := delete_world_files(worlds_dir, bad) {
			assert false, 'delete_world_files accepted illegal name "${bad}"'
		}
	}
	// The traversal attempt must not have touched the sibling.
	assert os.is_dir(victim)
}

fn test_delete_nonexistent_world_errors() {
	worlds_dir := temp_worlds_dir()
	defer {
		os.rmdir_all(worlds_dir) or {}
	}
	if _ := delete_world_files(worlds_dir, 'ghost') {
		assert false, 'deleting a missing world should error'
	}
}

fn test_delete_removes_only_the_named_world() {
	worlds_dir := temp_worlds_dir()
	defer {
		os.rmdir_all(worlds_dir) or {}
	}
	make_world_on_disk(worlds_dir, 'alpha')
	make_world_on_disk(worlds_dir, 'beta')
	assert world_exists(worlds_dir, 'alpha')
	assert world_exists(worlds_dir, 'beta')

	delete_world_files(worlds_dir, 'alpha')!
	assert !world_exists(worlds_dir, 'alpha')
	assert world_exists(worlds_dir, 'beta')
}

fn test_world_exists_rejects_illegal_names() {
	worlds_dir := temp_worlds_dir()
	defer {
		os.rmdir_all(worlds_dir) or {}
	}
	assert !world_exists(worlds_dir, '../etc')
	assert !world_exists(worlds_dir, '')
	assert !world_exists(worlds_dir, 'missing')
}
