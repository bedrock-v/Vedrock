module network

import os
import net
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
	mut ctx := ListenerContext{
		status: Status{
			network_id: 7
		}
	}
	mut l := listen_lan(LanConfig{
		address:       '127.0.0.1'
		port:          0
		identity_file: key_path('lan.pem')
	}, mut ctx) or { panic(err) }
	assert l.signalling.id() == 7
	l.close()
}

fn test_taken_media_port_is_refused() {
	mut held := net.listen_udp('0.0.0.0:0') or { panic(err) }
	defer {
		held.close() or {}
	}
	port := held.sock.address() or { panic(err) }.port() or { panic(err) }
	mut ctx := ListenerContext{
		media_port: port
	}
	if _ := ctx.media() {
		ctx.close()
		assert false, 'the media port was bound while somebody held it'
	}
}
