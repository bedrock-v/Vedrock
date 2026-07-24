module encryption

import crypto.rand
import crypto.sha256
import encoding.base64
import x.json2

const salt_len = 16

// HandshakeResult carries the two outputs of the handshake preparation: the
// derived AES-256 key (kept server-side to build the Context) and the signed
// ServerToClientHandshake JWT sent to the client.
pub struct HandshakeResult {
pub:
	key           []u8
	handshake_jwt string
}

// prepare_handshake runs the full server side of the Bedrock encryption
// handshake for one client: generate the server keypair, ECDH against the
// client public key, derive the AES key from a fresh random salt, and build a
// signed ServerToClientHandshake JWT. The keypair is freed before returning.
pub fn prepare_handshake(client_public_key_b64 string) !HandshakeResult {
	mut keys := new_server_key_pair()!
	defer {
		keys.free()
	}
	secret := keys.derive_shared_secret(client_public_key_b64)!
	salt := rand.bytes(salt_len)!
	key := derive_key(salt, secret)
	jwt := build_handshake_jwt(mut keys, salt)!
	return HandshakeResult{
		key:           key
		handshake_jwt: jwt
	}
}

// derive_key computes the AES-256 key as sha256(salt || sharedSecret).
fn derive_key(salt []u8, shared_secret []u8) []u8 {
	mut buf := []u8{cap: salt.len + shared_secret.len}
	buf << salt
	buf << shared_secret
	return sha256.sum256(buf)
}

// build_handshake_jwt builds the ES384-signed ServerToClientHandshake JWT. The
// header x5u is the server SPKI DER (base64), and the payload carries the salt.
fn build_handshake_jwt(mut keys ServerKeyPair, salt []u8) !string {
	der := keys.public_key_der()!
	header := json2.Any({
		'alg': json2.Any('ES384')
		'x5u': json2.Any(base64.encode(der))
	})
	payload := json2.Any({
		'salt': json2.Any(base64.url_encode(salt).trim_right('='))
	})
	signing_input := '${b64url_encode_json(header)}.${b64url_encode_json(payload)}'
	raw_sig := keys.sign_es384(signing_input.bytes())!
	return '${signing_input}.${base64.url_encode(raw_sig).trim_right('=')}'
}

fn b64url_encode_json(v json2.Any) string {
	return base64.url_encode(v.json_str().bytes()).trim_right('=')
}
