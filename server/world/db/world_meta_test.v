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

	mut store := create_world_store(dir, name, world.nether, 'nether', 1, world.SpawnPoint{ y: 64 }) or {
		panic(err)
	}
	store.close() or { panic(err) }

	mut loaded := load_named(dir, name, 'flat', world.overworld) or { panic(err) }
	assert loaded.dimension.id == world.nether.id
	assert loaded.generator_name == 'nether'
	loaded.close() or { panic(err) }
}

fn test_create_world_store_persists_end_dimension() {
	dir := meta_test_worlds_dir()
	defer {
		os.rmdir_all(dir) or {}
	}
	name := 'end_meta_test'

	mut store := create_world_store(dir, name, world.the_end, 'end', 1, world.SpawnPoint{ y: 4 }) or {
		panic(err)
	}
	store.close() or { panic(err) }

	mut loaded := load_named(dir, name, 'flat', world.overworld) or { panic(err) }
	assert loaded.dimension.id == world.the_end.id
	assert loaded.generator_name == 'end'
	loaded.close() or { panic(err) }
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
	store.close() or { panic(err) }

	mut loaded := load_named(dir, name, 'flat', world.overworld) or { panic(err) }
	assert loaded.dimension.id == world.overworld.id
	assert loaded.generator_name == 'flat'
	assert loaded.seed == 0
	loaded.close() or { panic(err) }
}

fn test_a_world_keeps_the_seed_it_was_created_with() {
	dir := meta_test_worlds_dir()
	defer {
		os.rmdir_all(dir) or {}
	}
	mut store := create_world_store(dir, 'seeded', world.overworld, 'normal', -1234567890123,
		world.SpawnPoint{ x: -40, y: 70, z: 12 }) or {
		panic(err)
	}
	store.close() or { panic(err) }

	mut loaded := load_named(dir, 'seeded', 'flat', world.overworld) or { panic(err) }
	assert loaded.seed == -1234567890123
	stored := loaded.spawn_point or { panic('the spawn was not kept') }
	assert stored == world.SpawnPoint{
		x: -40
		y: 70
		z: 12
	}
	loaded.close() or { panic(err) }
}

fn test_a_meta_file_from_before_seeds_means_seed_zero() {
	dir := meta_test_worlds_dir()
	defer {
		os.rmdir_all(dir) or {}
	}
	full := os.join_path(dir, 'pre_seed')
	os.mkdir_all(full) or { panic(err) }
	os.write_file(os.join_path(full, meta_filename), 'generator: normal\ndimension: 0\n') or {
		panic(err)
	}

	mut loaded := load_named(dir, 'pre_seed', 'flat', world.overworld) or { panic(err) }
	assert loaded.generator_name == 'normal'
	assert loaded.seed == 0
	loaded.close() or { panic(err) }
}

fn test_a_seed_that_is_not_a_number_is_an_error_rather_than_seed_zero() {
	dir := meta_test_worlds_dir()
	defer {
		os.rmdir_all(dir) or {}
	}
	full := os.join_path(dir, 'bad_seed')
	os.mkdir_all(full) or { panic(err) }
	os.write_file(os.join_path(full, meta_filename), 'generator: normal\ndimension: 0\nseed: banana\n') or {
		panic(err)
	}

	load_named(dir, 'bad_seed', 'flat', world.overworld) or { return }
	assert false, 'a world whose seed could not be read was loaded'
}

fn test_a_meta_file_that_cannot_be_read_is_an_error() {
	dir := meta_test_worlds_dir()
	defer {
		os.rmdir_all(dir) or {}
	}
	full := os.join_path(dir, 'unreadable')
	os.mkdir_all(os.join_path(full, meta_filename)) or { panic(err) }

	load_named(dir, 'unreadable', 'flat', world.overworld) or { return }
	assert false, 'a world whose meta file could not be read was loaded'
}

fn test_a_meta_file_naming_no_generator_is_an_error() {
	dir := meta_test_worlds_dir()
	defer {
		os.rmdir_all(dir) or {}
	}
	full := os.join_path(dir, 'no_generator')
	os.mkdir_all(full) or { panic(err) }
	os.write_file(os.join_path(full, meta_filename), 'dimension: 0\nseed: 5\n') or { panic(err) }

	load_named(dir, 'no_generator', 'flat', world.overworld) or { return }
	assert false, 'a world whose meta file names no generator was loaded'
}
