module server

import os
import encoding.base64
import x.json2
import server.conf
import server.resource
import server.world
import server.session
import server.internal.auth
import server.player.playerdb

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

fn test_late_registered_generator_is_used_by_worlds() {
	mut srv := new(settings: isolated_config('gen', 19150)) or {
		panic('server failed to start: ${err}')
	}
	srv.register_generator('custom-spawn', fn (dim world.Dimension) world.Generator {
		return CustomSpawnGenerator{}
	})

	w := srv.load_world(name: 'test', generator_name: 'custom-spawn') or {
		panic('expected world to load: ${err}')
	}
	assert w.spawn_y() == 12345
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

// InMemoryPlayerProvider is a minimal playerdb.Provider backed by a map.
struct InMemoryPlayerProvider {
mut:
	data map[string]playerdb.PlayerData
}

fn (p &InMemoryPlayerProvider) load(key string) ?playerdb.PlayerData {
	return p.data[key] or { return none }
}

fn (mut p InMemoryPlayerProvider) save(key string, data playerdb.PlayerData) ! {
	p.data[key] = data
}

fn test_custom_player_data_provider_is_used() {
	mut provider := &InMemoryPlayerProvider{
		data: map[string]playerdb.PlayerData{}
	}
	provider_iface := playerdb.Provider(provider)
	mut srv := new(
		settings:    isolated_config('playerdb', 19152)
		hub_options: session.HubOptions{
			player_data_provider: provider_iface
		}
	) or { panic('server failed to start: ${err}') }

	mut prov := srv.hub.player_data_provider
	prov.save('Alex', playerdb.PlayerData{
		x: 5.0
		y: 6.0
		z: 7.0
	}) or { panic('save failed: ${err}') }

	loaded := srv.hub.player_data_provider.load('Alex') or { panic('expected saved data') }
	assert loaded.x == 5.0
	// Confirms the write actually landed in the custom provider.
	assert provider.data['Alex'].x == 5.0
}

// MockVerifier stands in for a fully custom or mocked auth.Verifier
// (federated auth, testing).
struct MockVerifier {
mut:
	calls int
}

fn (mut v MockVerifier) verify(token string) !map[string]json2.Any {
	v.calls++
	return map[string]json2.Any{}
}

fn unsigned_test_token(payload_json string) string {
	header := base64.url_encode('{"alg":"none"}'.bytes()).trim_right('=')
	payload := base64.url_encode(payload_json.bytes()).trim_right('=')
	return '${header}.${payload}.spoofed'
}

fn test_parse_login_chain_uses_custom_auth_verifier() {
	mut verifier := &MockVerifier{}
	verifier_iface := auth.Verifier(verifier)
	mut srv := new(
		settings:    isolated_config('auth', 19154)
		hub_options: session.HubOptions{
			auth_verifier: verifier_iface
		}
	) or { panic('server failed to start: ${err}') }

	token :=
		unsigned_test_token('{"xid":"1234567890","xname":"Alex","identity":"00000000-0000-0000-0000-000000000002"}')
	chain_json := '{"Token":"${token}"}'
	identity := auth.parse_login_chain(chain_json, false, mut srv.hub.oidc_verifier) or {
		panic('parse_login_chain failed: ${err}')
	}
	assert verifier.calls == 1
	assert identity.display_name == 'Alex'
}
