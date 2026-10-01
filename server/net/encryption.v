module net

import crypto.rand
import crypto.sha256
import encoding.base64
import x.json2

const salt_len = 16

// Encryption is what the server needs to start encrypting. It holds the cipher
// built from the derived key, and the token the client needs to build the same
// one.
struct Encryption {
	cipher &Cipher
	jwt    string
}

// prepare_encryption runs the server side of the game's encryption handshake
// for one client. It makes a fresh keypair, derives a shared secret from the
// client's public key, turns that secret and a random salt into the session key,
// and signs the token that tells the client the salt. The keypair is freed
// before returning, since nothing after this handshake needs it.
fn prepare_encryption(client_public_key_b64 string) !Encryption {
	mut keys := new_server_key_pair()!
	defer {
		keys.free()
	}
	secret := keys.derive_shared_secret(client_public_key_b64)!
	salt := rand.bytes(salt_len)!
	key := derive_key(salt, secret)
	jwt := build_handshake_jwt(mut keys, salt)!
	return Encryption{
		cipher: new_cipher(key)!
		jwt:    jwt
	}
}

// derive_key computes the AES-256 key as sha256(salt || sharedSecret).
fn derive_key(salt []u8, shared_secret []u8) []u8 {
	mut buf := []u8{cap: salt.len + shared_secret.len}
	buf << salt
	buf << shared_secret
	return sha256.sum256(buf)
}

// build_handshake_jwt builds the signed token for ServerToClientHandshake. Its
// header carries the server's public key and its payload the salt, which is
// everything the client needs to derive the same key.
fn build_handshake_jwt(mut keys ServerKeyPair, salt []u8) !string {
	der := keys.public_key_der()!
	header := json2.Any({
		'alg': json2.Any('ES384')
		'x5u': json2.Any(base64.encode(der))
	})
	payload := json2.Any({
		'salt': json2.Any(base64.encode(salt).trim_right('='))
	})
	signing_input := '${b64url_encode_json(header)}.${b64url_encode_json(payload)}'
	raw_sig := keys.sign_es384(signing_input.bytes())!
	return '${signing_input}.${base64.url_encode(raw_sig).trim_right('=')}'
}

fn b64url_encode_json(v json2.Any) string {
	return base64.url_encode(v.json_str().bytes()).trim_right('=')
}
