module session

import os
import server.internal.gamedata
import server.internal.language
import server.internal.logger
import server.world
import server.world.db

// FakeProvider is a purely in memory db.Provider.
struct FakeProvider {
mut:
	columns map[string][]u8
}

fn (p &FakeProvider) dimension() world.Dimension {
	return world.overworld
}

fn (p &FakeProvider) load_chunk(cx int, cz int) ?world.Chunk {
	return none
}

fn (mut p FakeProvider) store_column(cx int, cz int, data []u8) ! {
	p.columns['${cx},${cz}'] = data.clone()
}

fn (p &FakeProvider) load_column(cx int, cz int) ?[]u8 {
	return p.columns['${cx},${cz}'] or { return none }
}

fn (p &FakeProvider) each_player_spawn(cb fn (key string, x int, y int, z int)) {}

fn (mut p FakeProvider) store_chunk_blocks(cx int, cz int, encoded map[int][]u8) ! {}

fn (mut p FakeProvider) set_player_spawn(key string, x int, y int, z int) ! {}

fn (mut p FakeProvider) flush() ! {}

fn (mut p FakeProvider) close() ! {}

// FakeFactory hands out FakeProvider instead of touching disk at all.
struct FakeFactory {
mut:
	created []string
	seeds   []i64
}

fn (f &FakeFactory) exists(name string) bool {
	return false
}

fn (mut f FakeFactory) create(name string, dim world.Dimension, generator string, seed i64) !db.Provider {
	f.created << name
	f.seeds << seed
	return &FakeProvider{}
}

fn (mut f FakeFactory) open(name string, fallback_generator string, fallback_dim world.Dimension) !&db.World {
	return error('FakeFactory has nothing to open')
}

fn (f &FakeFactory) discover() []string {
	return []
}

fn (mut f FakeFactory) delete(name string) ! {}

fn test_hub_creates_world_through_custom_factory() {
	mut factory := &FakeFactory{}
	mut hub := new_hub(gamedata.GameData{}, world_factory: db.Factory(factory))
	hub.set_world_config('unused-worlds-dir', 'flat')

	hub.create_world('custom', world.overworld, 'flat', none) or {
		panic('expected create_world to succeed: ${err}')
	}

	assert factory.created == ['custom']
	assert factory.seeds.len == 1 && factory.seeds[0] != 0
	created := hub.world('custom') or { panic('expected the created world to be loaded') }
	assert created.seed == factory.seeds[0]
	info := hub.world_info('custom') or { panic('expected world_info to find it') }
	assert info.name == 'custom'
}

fn test_a_default_world_created_at_boot_records_its_seed() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_boot_seed_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	mut hub := new_hub(gamedata.GameData{},
		world_factory: db.Factory(db.LevelDBFactory{
			worlds_dir: dir
		})
	)
	defer {
		hub.close_worlds()
	}
	lang := language.load('en') or { panic(err) }

	hub.load_configured_worlds(dir, 'world', false, 'normal', logger.new(.info), lang)

	created := hub.world('world') or { panic('the default world was not created') }
	assert created.seed != 0
	meta := os.read_file(os.join_path(dir, 'world', 'meta.txt')) or {
		panic('the default world has no meta.txt')
	}
	assert meta.contains('seed: ${created.seed}')
}

fn test_a_world_s_seed_reaches_the_generator_built_for_it() {
	mut hub := new_hub(gamedata.GameData{})
	mut seeded := db.new_world('seeded', none, 'normal', world.overworld)
	seeded.seed = 42
	legacy := db.new_world('legacy', none, 'normal', world.overworld)

	assert sample_block_ids(hub.build_generator(seeded)) != sample_block_ids(hub.build_generator(legacy))
}

fn sample_block_ids(g world.Generator) []int {
	mut ids := []int{}
	for pos in [[0, 0], [300, -120]] {
		for y in 0 .. 128 {
			ids << g.block_at(pos[0], y, pos[1])
		}
	}
	return ids
}
