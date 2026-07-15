module playerdb

import os

fn test_save_then_load_roundtrip() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_playerdb_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	data := PlayerData{
		x:        1.5
		y:        64.0
		z:        -3.25
		gamemode: 1
		items:    [InvItem{
			id:    5
			count: 12
		}]
	}
	save_player(dir, 'abc', data) or {
		assert false, 'save failed: ${err}'
		return
	}
	loaded := load_player(dir, 'abc') or {
		assert false, 'load returned none'
		return
	}
	assert loaded.x == 1.5
	assert loaded.y == 64.0
	assert loaded.items.len == 1
	assert loaded.items[0].id == 5
}

fn test_save_leaves_no_temp_file() {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_playerdb_tmp_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	save_player(dir, 'key', PlayerData{}) or {
		assert false, 'save failed: ${err}'
		return
	}
	entries := os.ls(dir) or {
		assert false, 'ls failed'
		return
	}
	for e in entries {
		assert !e.contains('.tmp.'), 'temp file left behind: ${e}'
	}
	assert os.exists(os.join_path(dir, 'key.json'))
}

fn test_safe_key_blocks_path_traversal() {
	// A malicious display name must never escape the players dir - the result
	// carries no separator, parent-dir sequence, or drive colon.
	for evil in ['../../ops', 'a/b/c', 'C:\\evil', '..\\..\\x', '/etc/passwd'] {
		k := safe_key(evil)
		assert !k.contains('/')
		assert !k.contains('\\')
		assert !k.contains('..')
		assert !k.contains(':')
		assert k != ''
	}
	// Normal keys pass through unchanged.
	assert safe_key('Steve') == 'Steve'
	assert safe_key('2535412345678901') == '2535412345678901'
	// Empty / dot-only degrade to a non-empty safe stem.
	assert safe_key('') == 'unknown'
	assert safe_key('...') != ''
}
