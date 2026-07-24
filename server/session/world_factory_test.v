module session

import server.internal.gamedata
import server.world
import server.world.db

// FakeProvider is a purely in memory db.Provider.
struct FakeProvider {
mut:
	blocks map[string]int
}

fn (p &FakeProvider) dimension() world.Dimension {
	return world.overworld
}

fn (p &FakeProvider) load_chunk(cx int, cz int) ?world.Chunk {
	return none
}

fn (mut p FakeProvider) set_block(x int, y int, z int, runtime_id int) {
	p.blocks['${x},${y},${z}'] = runtime_id
}

fn (p &FakeProvider) each_block(cb fn (x int, y int, z int, runtime_id int)) {}

fn (mut p FakeProvider) set_tile_text(x int, y int, z int, text string) {}

fn (p &FakeProvider) each_tile(cb fn (x int, y int, z int, text string)) {}

fn (mut p FakeProvider) flush() {}

fn (mut p FakeProvider) close() {}

// FakeFactory hands out FakeProvider instead of touching disk at all.
struct FakeFactory {
mut:
	created []string
}

fn (f &FakeFactory) exists(name string) bool {
	return false
}

fn (mut f FakeFactory) create(name string, dim world.Dimension, generator string) !db.Provider {
	f.created << name
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

	hub.create_world('custom', world.overworld, 'flat') or {
		panic('expected create_world to succeed: ${err}')
	}

	assert factory.created == ['custom']
	info := hub.world_info('custom') or { panic('expected world_info to find it') }
	assert info.name == 'custom'
}
