module encryption

import encoding.base64

// test_handshake_end_to_end acts as both server and client: it generates a
// "client" P-384 keypair, feeds its SPKI to prepare_handshake, and checks that
// the ECDH derive, key derivation, and JWT signing all succeed and produce a
// usable 32-byte key plus a three-part JWT.
fn test_handshake_end_to_end() {
	mut client := new_server_key_pair()!
	defer {
		client.free()
	}
	client_der := client.public_key_der()!
	assert client_der.len > 0
	result := prepare_handshake(base64.encode(client_der))!
	assert result.key.len == 32
	parts := result.handshake_jwt.split('.')
	assert parts.len == 3
	for part in parts {
		assert part.len > 0
	}
}

// test_shared_secret_symmetry proves ECDH agreement: server<-client and
// client<-server must derive the identical secret.
fn test_shared_secret_symmetry() {
	mut a := new_server_key_pair()!
	mut b := new_server_key_pair()!
	defer {
		a.free()
		b.free()
	}
	a_der := base64.encode(a.public_key_der()!)
	b_der := base64.encode(b.public_key_der()!)
	secret_ab := a.derive_shared_secret(b_der)!
	secret_ba := b.derive_shared_secret(a_der)!
	assert secret_ab.len == 48
	assert secret_ab == secret_ba
}

fn test_invalid_client_key_rejected() {
	mut server := new_server_key_pair()!
	defer {
		server.free()
	}
	if _ := server.derive_shared_secret('not-valid-base64-der!!!') {
		assert false, 'expected error for invalid client key'
	}
}
