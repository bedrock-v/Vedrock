module db

import os
import rand
import server.world

fn meta_test_worlds_dir() string {
	dir := os.join_path(os.temp_dir(), 'vedrock_meta_test_${os.getpid()}_${rand.i64()}')
	os.mkdir_all(dir) or { panic(err) }
	return dir
}

fn test_create_world_store_persists_meta_and_load_named_restores_it() {
	dir := meta_test_worlds_dir()
	defer {
		os.rmdir_all(dir) or {}
	}
	name := 'nether_meta_test'

	mut store := create_world_store(dir, name, world.nether, 'nether') or { panic(err) }
	store.close()

	mut loaded := load_named(dir, name, 'flat', world.overworld) or { panic(err) }
	assert loaded.dimension.id == world.nether.id
	assert loaded.generator_name == 'nether'
	loaded.close()
}

fn test_create_world_store_persists_end_dimension() {
	dir := meta_test_worlds_dir()
	defer {
		os.rmdir_all(dir) or {}
	}
	name := 'end_meta_test'

	mut store := create_world_store(dir, name, world.the_end, 'end') or { panic(err) }
	store.close()

	mut loaded := load_named(dir, name, 'flat', world.overworld) or { panic(err) }
	assert loaded.dimension.id == world.the_end.id
	assert loaded.generator_name == 'end'
	loaded.close()
}

fn test_load_named_falls_back_when_meta_file_is_absent() {
	dir := meta_test_worlds_dir()
	defer {
		os.rmdir_all(dir) or {}
	}
	name := 'legacy_world'

	full := os.join_path(dir, name)
	os.mkdir_all(full) or { panic(err) }
	mut store := open_world(os.join_path(full, 'db'), world.overworld) or { panic(err) }
	store.close()

	mut loaded := load_named(dir, name, 'flat', world.overworld) or { panic(err) }
	assert loaded.dimension.id == world.overworld.id
	assert loaded.generator_name == 'flat'
	loaded.close()
}
