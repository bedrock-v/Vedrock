module resourcepack

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

const test_key = '01234567890123456789012345678901'

fn make_encrypted_pack(path string, manifest string) ! {
	mut contents := []u8{len: 8}
	contents[4] = 0xfc
	contents[5] = 0xb9
	contents[6] = 0xcf
	contents[7] = 0x9b
	mut z := szip.open(path, .best_compression, .write)!
	z.create_entry('manifest.json')!
	z.write_entry(manifest.bytes())!
	z.create_entry('contents.json')!
	z.write_entry(contents)!
	z.close()
}

fn test_local_pack_reads_key_file() {
	dir := os.join_path(os.temp_dir(), 'vedrock_rp_key_test')
	os.mkdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'test.mcpack')
	manifest := '{"header":{"uuid":"${test_uuid}","version":[1,0,0]}}'
	make_encrypted_pack(path, manifest) or {
		eprintln('skip: cannot build zip: ${err}')
		return
	}
	assert is_encrypted(path) or { false }
	if _ := new_local_pack(path) {
		assert false, 'encrypted pack loaded without a key file'
	}
	os.write_file(path + key_file_suffix, test_key) or {
		assert false, 'cannot write key file'
		return
	}
	pack := new_local_pack(path) or {
		assert false, 'load failed: ${err}'
		return
	}
	assert pack.content_key == test_key
	assert pack.has_content_key()
}

fn test_local_pack_rejects_malformed_key() {
	dir := os.join_path(os.temp_dir(), 'vedrock_rp_badkey_test')
	os.mkdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'test.mcpack')
	manifest := '{"header":{"uuid":"${test_uuid}","version":[1,0,0]}}'
	make_pack(path, manifest) or {
		eprintln('skip: cannot build zip: ${err}')
		return
	}
	os.write_file(path + key_file_suffix, 'too-short') or {
		assert false, 'cannot write key file'
		return
	}
	if _ := new_local_pack(path) {
		assert false, 'pack loaded with a malformed key'
	}
}

fn test_plain_pack_has_no_key() {
	dir := os.join_path(os.temp_dir(), 'vedrock_rp_plain_test')
	os.mkdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'test.mcpack')
	manifest := '{"header":{"uuid":"${test_uuid}","version":[1,0,0]}}'
	make_pack(path, manifest) or {
		eprintln('skip: cannot build zip: ${err}')
		return
	}
	assert !(is_encrypted(path) or { true })
	pack := new_local_pack(path) or {
		assert false, 'load failed: ${err}'
		return
	}
	assert pack.content_key == ''
	assert !pack.has_content_key()
}

fn test_unreadable_pack_fails_rather_than_loading_unkeyed() {
	dir := os.join_path(os.temp_dir(), 'vedrock_rp_broken_test')
	os.mkdir_all(dir) or {}
	defer {
		os.rmdir_all(dir) or {}
	}
	path := os.join_path(dir, 'broken.mcpack')
	os.write_file(path, 'not a zip') or {
		assert false, 'cannot write file'
		return
	}
	if _ := is_encrypted(path) {
		assert false, 'unreadable pack reported an encryption verdict'
	}
	if _ := new_local_pack(path) {
		assert false, 'unreadable pack loaded'
	}
}

fn test_with_content_key() {
	pack := new_cdn_pack(test_uuid, '1.0.0', 'https://a/b.zip', 0) or {
		assert false
		return
	}
	keyed := pack.with_content_key(test_key) or {
		assert false, 'key rejected: ${err}'
		return
	}
	assert keyed.content_key == test_key
	assert keyed.uuid == test_uuid
	assert keyed.cdn_url == 'https://a/b.zip'
	assert pack.content_key == ''
	if _ := pack.with_content_key('short') {
		assert false, 'malformed key accepted'
	}
}

fn test_parse_cdn_packs_with_key() {
	packs := parse_cdn_packs('${test_uuid},1.0.0,https://a/b.zip,100,${test_key}')
	assert packs.len == 1
	assert packs[0].content_key == test_key
	// An entry whose key is unusable is dropped rather than served unkeyed.
	assert parse_cdn_packs('${test_uuid},1.0.0,https://a/b.zip,100,short').len == 0
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
