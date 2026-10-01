module net

import encoding.base64
import encoding.hex

fn test_a_message_survives_encryption() {
	key := []u8{len: 32, init: u8(index)}
	mut server := new_cipher(key) or { panic(err) }
	mut client := new_cipher(key) or { panic(err) }
	message := 'the quick brown fox'.bytes()
	assert client.decrypt(server.encrypt(message)) or { panic(err) } == message
}

fn test_messages_decode_in_the_order_they_were_encrypted() {
	key := []u8{len: 32, init: u8(index * 7)}
	mut server := new_cipher(key) or { panic(err) }
	mut client := new_cipher(key) or { panic(err) }
	mut sent := [][]u8{}
	for i in 0 .. 8 {
		sent << server.encrypt('message ${i}'.bytes())
	}
	for i, message in sent {
		assert client.decrypt(message) or { panic(err) } == 'message ${i}'.bytes()
	}
}

fn test_a_message_decoded_out_of_order_is_refused() {
	key := []u8{len: 32, init: u8(index)}
	mut server := new_cipher(key) or { panic(err) }
	mut client := new_cipher(key) or { panic(err) }
	_ := server.encrypt('first'.bytes())
	second := server.encrypt('second'.bytes())
	if _ := client.decrypt(second) {
		assert false, 'a message decoded out of order was accepted'
	}
}

fn test_a_tampered_message_is_refused() {
	key := []u8{len: 32, init: u8(index)}
	mut server := new_cipher(key) or { panic(err) }
	mut client := new_cipher(key) or { panic(err) }
	mut message := server.encrypt('do not change me'.bytes())
	message[3] = ~message[3]
	if _ := client.decrypt(message) {
		assert false, 'a tampered message was accepted'
	}
}

const openssl_p384_spki = '3076301006072a8648ce3d020106052b81040022036200047603ab9946d88aea4b191aa5414277b541b1f76ea1c2d287df301322113de9b569c65e55448ea5535e40fecda5c4989013cd40588563f88b91e4b4d3f09f328f83c2e07a62a2a262a66841dd5d36e630bc24961031947c4cc6472a633ee88121'

fn test_the_spki_header_matches_openssl() {
	der := hex.decode(openssl_p384_spki) or { panic(err) }
	assert der.len == p384_spki_prefix.len + p384_point_size
	assert der[..p384_spki_prefix.len] == p384_spki_prefix
	assert spki_from_p384_point(der[p384_spki_prefix.len..]) or { panic(err) } == der
}

fn test_a_key_that_is_not_p384_is_refused() {
	if _ := p384_public_key_from_spki([]u8{len: 10}) {
		assert false, 'a short SubjectPublicKeyInfo was accepted'
	}
	mut wrong := []u8{len: p384_spki_prefix.len + p384_point_size}
	wrong[0] = 0x31
	if _ := p384_public_key_from_spki(wrong) {
		assert false, 'a SubjectPublicKeyInfo on another curve was accepted'
	}
}

fn test_both_ends_derive_the_same_key() {
	mut server := new_server_key_pair() or { panic(err) }
	mut client := new_server_key_pair() or { panic(err) }
	defer {
		server.free()
		client.free()
	}
	server_public := base64_spki(server)
	client_public := base64_spki(client)
	salt := []u8{len: 16, init: u8(index)}
	server_key := derive_key(salt, server.derive_shared_secret(client_public) or { panic(err) })
	client_key := derive_key(salt, client.derive_shared_secret(server_public) or { panic(err) })
	assert server_key == client_key
	assert server_key.len == 32
}

fn test_a_malformed_client_key_is_refused() {
	mut keys := new_server_key_pair() or { panic(err) }
	defer {
		keys.free()
	}
	for bad in ['', 'not base64 at all!!', 'aGVsbG8='] {
		if _ := keys.derive_shared_secret(bad) {
			assert false, 'a client key of "${bad}" was accepted'
		}
	}
}

// base64_spki is a keypair's public key in the form the game carries keys in.
fn base64_spki(k &ServerKeyPair) string {
	return base64.encode(k.public_key_der() or { panic(err) })
}
