module network

import os
import crypto.ecdsa
import bedrock_v.nethernet as nn

fn key_path(name string) string {
	dir := os.join_path(os.vtmp_dir(), 'vedrock_identity_test_${os.getpid()}')
	os.rmdir_all(dir) or {}
	return os.join_path(dir, 'keys', name)
}

fn test_missing_key_is_generated_and_kept() {
	path := key_path('server_identity_key.pem')
	first := load_identity_key(path) or { panic(err) }
	$if !windows {
		assert os.inode(path).bitmask() & 0o777 == 0o600
	}
	second := load_identity_key(path) or { panic(err) }
	assert first.equal(second)
}

fn test_key_on_another_curve_is_refused() {
	path := key_path('p256.pem')
	os.mkdir_all(os.dir(path)) or { panic(err) }
	key := ecdsa.PrivateKey.new(nid: .prime256v1) or { panic(err) }
	os.write_file(path, nn.encode_private_key_pem(key) or { panic(err) }) or { panic(err) }
	if _ := load_identity_key(path) {
		assert false, 'a P-256 key was taken'
	}
}

fn test_lan_listener_binds_and_closes() {
	mut l := listen_lan(LanConfig{
		address:       '127.0.0.1'
		port:          0
		identity_file: key_path('lan.pem')
	}, Status{ network_id: 7 }) or { panic(err) }
	assert l.signalling.id() == 7
	l.close()
}
