module server

import os
import server.conf
import server.resource
import server.world
import server.world.db

// isolated_config builds a Config rooted entirely under a fresh temp
// directory, so these tests never touch (or race on) this repo's own
// working directory defaults the way a bare new() would.
fn isolated_config(name string, port int) conf.Config {
	dir := os.join_path(os.temp_dir(), 'vedrock_injection_points_test_${name}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err) }
	return conf.Config{
		port:                    port
		worlds_dir:              os.join_path(dir, 'worlds')
		crashdumps_dir:          os.join_path(dir, 'crashdumps')
		ops_file:                os.join_path(dir, 'ops.txt')
		permissions_file:        os.join_path(dir, 'permissions.yml')
		player_permissions_file: os.join_path(dir, 'player_permissions.yml')
		whitelist_file:          os.join_path(dir, 'whitelist.txt')
		resource_packs:          false
	}
}

// CustomSpawnGenerator is a minimal Generator whose only distinctive trait is
// an unusual spawn_y, enough to prove a real registered generator.
struct CustomSpawnGenerator {}

fn (g CustomSpawnGenerator) spawn_y() int {
	return 12345
}

fn (g CustomSpawnGenerator) uses_blocks() bool {
	return false
}

fn (g CustomSpawnGenerator) generate(chunk_x int, chunk_z int) world.Chunk {
	return world.Chunk{}
}

fn (g CustomSpawnGenerator) block_at(x int, y int, z int) int {
	return world.air.network_id
}

fn (g CustomSpawnGenerator) biome_at(x int, z int) int {
	return 0
}

// This test proves a framework user can register a custom generator on the
// already returned Server. register_generator/GeneratorRegistry.register were already pub before this
// pass, so no new Options field was needed to make this a real injection
// point: no player can connect before server.new() returns control, so
// there's always a safe window to call this before it matters.
fn test_late_registered_generator_is_used_by_worlds() {
	mut srv := new(settings: isolated_config('gen', 19150)) or {
		panic('server failed to start: ${err}')
	}
	srv.hub.register_generator('custom-spawn', fn (dim world.Dimension) world.Generator {
		return CustomSpawnGenerator{}
	})

	w := db.new_world('test', none, 'custom-spawn', world.overworld)
	gen := srv.hub.build_generator(w)
	assert gen.spawn_y() == 12345
}

// test_resource_pack_added_after_new_is_findable proves the same for
// resource packs. PackRegistry.add is already pub and cfg.resource_packs
// = false already gives a totally empty registry to add to, with no
// directory/CDN scanning at all.
fn test_resource_pack_added_after_new_is_findable() {
	mut srv := new(settings: isolated_config('pack', 19151)) or {
		panic('server failed to start: ${err}')
	}
	srv.hub.packs.add(&resource.ResourcePack{
		uuid:    'a1b2c3d4-0000-0000-0000-000000000000'
		version: '1.0.0'
	})

	found := srv.hub.packs.find('a1b2c3d4-0000-0000-0000-000000000000_1.0.0') or {
		panic('expected the added pack to be findable')
	}
	assert found.version == '1.0.0'
}
