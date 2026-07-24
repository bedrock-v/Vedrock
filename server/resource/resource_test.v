module resource

import os
import compress.szip

const test_uuid = '12345678-1234-1234-1234-123456789abc'

fn make_pack(path string, manifest string) ! {
	mut z := szip.open(path, .best_compression, .write)!
	z.create_entry('manifest.json')!
	z.write_entry(manifest.bytes())!
	z.close()
}

fn test_local_pack_loads() {
	dir := os.join_path(os.temp_dir(), 'vedrock_rp_test')
	os.mkdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'test.mcpack')
	manifest := '{"header":{"uuid":"${test_uuid}","version":[1,2,3]}}'
	make_pack(path, manifest) or {
		eprintln('skip: cannot build zip: ${err}')
		return
	}
	pack := new_local_pack(path) or {
		assert false, 'load failed: ${err}'
		return
	}
	assert pack.uuid == test_uuid
	assert pack.version == '1.2.3'
	assert pack.id() == '${test_uuid}_1.2.3'
	assert pack.uuid_bytes().len == 16
	assert pack.uuid_bytes()[0] == 0x12
	assert pack.sha256.len == 32
	assert !pack.is_cdn()
	assert pack.size > 0
	assert pack.chunk_count() == 1
	assert pack.chunk(0).len == int(pack.size)
	assert pack.chunk(1).len == 0
}

fn test_cdn_pack() {
	pack := new_cdn_pack(test_uuid, '2.0.0', 'https://cdn.example/pack.zip', 4096) or {
		assert false, 'cdn build failed'
		return
	}
	assert pack.is_cdn()
	assert pack.cdn_url == 'https://cdn.example/pack.zip'
	assert pack.chunk_count() == 0
}

fn test_parse_cdn_packs() {
	packs := parse_cdn_packs('${test_uuid},1.0.0,https://a/b.zip,100 ; ,broken')
	assert packs.len == 1
	assert packs[0].uuid == test_uuid
	assert packs[0].size == 100
	assert parse_cdn_packs('').len == 0
}

fn test_registry_find() {
	mut reg := &PackRegistry{}
	pack := new_cdn_pack(test_uuid, '1.0.0', 'https://a/b.zip', 0) or {
		assert false
		return
	}
	reg.add(pack)
	if p := reg.find('${test_uuid}_1.0.0') {
		assert p.uuid == test_uuid
	} else {
		assert false, 'find by full id failed'
	}
	if p := reg.find(test_uuid) {
		assert p.uuid == test_uuid
	} else {
		assert false, 'find by uuid failed'
	}
	if _ := reg.find('nope') {
		assert false, 'unexpectedly found missing pack'
	}
}

fn test_must_accept_needs_packs() {
	mut empty := &PackRegistry{}
	empty.set_must_accept(true)
	assert empty.must_accept == false
	mut reg := &PackRegistry{}
	reg.add(new_cdn_pack(test_uuid, '1.0.0', 'https://a/b.zip', 0) or { return })
	reg.set_must_accept(true)
	assert reg.must_accept == true
}
