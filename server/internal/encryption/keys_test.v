module encryption

import crypto.ecdsa

const openssl_p384_spki_hex = '3076301006072a8648ce3d020106052b81040022036200047603ab9946d88aea4b191aa5414277b541b1f76ea1c2d287df301322113de9b569c65e55448ea5535e40fecda5c4989013cd40588563f88b91e4b4d3f09f328f83c2e07a62a2a262a66841dd5d36e630bc24961031947c4cc6472a633ee88121'

fn spki_vector() []u8 {
	mut out := []u8{cap: openssl_p384_spki_hex.len / 2}
	for i := 0; i < openssl_p384_spki_hex.len; i += 2 {
		out << u8(('0x' + openssl_p384_spki_hex[i..i + 2]).u8())
	}
	return out
}

// test_p384_spki_prefix_matches_openssl pins the hardcoded ASN.1 header against
// output from OpenSSL itself.
fn test_p384_spki_prefix_matches_openssl() {
	vector := spki_vector()
	assert vector.len == p384_spki_prefix.len + p384_point_size
	assert vector[..p384_spki_prefix.len] == p384_spki_prefix
}

// test_spki_from_point_rebuilds_openssl_der proves the concatenation reproduces
// a real i2d_PUBKEY result byte for byte.
fn test_spki_from_point_rebuilds_openssl_der() {
	vector := spki_vector()
	point := vector[p384_spki_prefix.len..]
	assert spki_from_p384_point(point)! == vector
}

fn test_spki_from_point_rejects_a_bad_point() {
	if _ := spki_from_p384_point([]u8{len: 10}) {
		assert false, 'expected an error for a short point'
	}
	mut compressed := []u8{len: p384_point_size}
	compressed[0] = 0x03
	if _ := spki_from_p384_point(compressed) {
		assert false, 'expected an error for a non-uncompressed point'
	}
}

// test_generated_spki_parses_back proves the SPKI we hand the client is valid
// DER: OpenSSL's own parser reads it back to the same point.
fn test_generated_spki_parses_back() {
	mut keys := new_server_key_pair()!
	defer {
		keys.free()
	}
	der := keys.public_key_der()!
	assert der.len == p384_spki_prefix.len + p384_point_size
	parsed := ecdsa_pubkey_for_test(der)!
	defer {
		parsed.free()
	}
	assert parsed.bytes()! == der[p384_spki_prefix.len..]
}

// test_free_is_idempotent guards the double free that crypto.ecdsa's own free
// would otherwise allow.
fn test_free_is_idempotent() {
	mut keys := new_server_key_pair()!
	keys.free()
	keys.free()
}

// ecdsa_pubkey_for_test parses SPKI DER the same way derive_shared_secret does.
fn ecdsa_pubkey_for_test(der []u8) !ecdsa.PublicKey {
	return ecdsa.pubkey_from_string(pem_from_spki_der(der))!
}
