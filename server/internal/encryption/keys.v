module encryption

import crypto.ecdsa
import encoding.base64

// The Bedrock encryption handshake needs a P-384 keypair, an ECDH derive
// against the client key and an ES384 signature. crypto.ecdsa does all three;
// this file only bridges the key format. Bedrock carries public keys as base64
// SubjectPublicKeyInfo DER while crypto.ecdsa, on its default backend, reads
// and writes only the raw EC point. For P-384 an SPKI is that point behind a
// fixed header, so the conversion is done here in both directions.

// p384_spki_prefix is the SubjectPublicKeyInfo header for a secp384r1 key: the
// SEQUENCE, the id-ecPublicKey/secp384r1 AlgorithmIdentifier and the BIT
// STRING tag. It is fixed for the curve, so an SPKI is this prefix followed by
// the uncompressed point. Pinned by keys_test.v against real OpenSSL output.
const p384_spki_prefix = [u8(0x30), 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d,
	0x02, 0x01, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00]

// An uncompressed P-384 point is 0x04 followed by two 48 byte coordinates.
const p384_point_size = 97

const p384_component_size = 48

// ServerKeyPair holds the ephemeral P-384 ECDH/signing keypair the server
// generates once per session for the encryption handshake. It owns two
// crypto.ecdsa key handles and must be freed when the handshake is done.
pub struct ServerKeyPair {
mut:
	private_key ecdsa.PrivateKey
	public_key  ecdsa.PublicKey
	freed       bool
}

// new_server_key_pair generates a fresh secp384r1 keypair.
pub fn new_server_key_pair() !&ServerKeyPair {
	public_key, private_key := ecdsa.generate_key(nid: .secp384r1)!
	return &ServerKeyPair{
		private_key: private_key
		public_key: public_key
	}
}

// free releases both key handles. Idempotent: crypto.ecdsa's own free is not,
// so the guard keeps a second call from double freeing.
pub fn (mut k ServerKeyPair) free() {
	if k.freed {
		return
	}
	k.freed = true
	k.private_key.free()
	k.public_key.free()
}

// public_key_der returns the server's SubjectPublicKeyInfo (SPKI) DER bytes,
// used as the base64 x5u header of the ServerToClientHandshake JWT.
pub fn (k &ServerKeyPair) public_key_der() ![]u8 {
	return spki_from_p384_point(k.public_key.bytes()!)
}

// spki_from_p384_point wraps an uncompressed EC point in SPKI DER.
fn spki_from_p384_point(point []u8) ![]u8 {
	if point.len != p384_point_size || point[0] != 0x04 {
		return error('expected a ${p384_point_size}-byte uncompressed P-384 point, got ${point.len} bytes')
	}
	mut out := []u8{cap: p384_spki_prefix.len + point.len}
	out << p384_spki_prefix
	out << point
	return out
}

// p384_public_key_from_spki reads a P-384 SubjectPublicKeyInfo, the form
// Bedrock carries every public key in: the client's handshake key and each key
// in the login chain. A key on any other curve is refused.
pub fn p384_public_key_from_spki(der []u8) !ecdsa.PublicKey {
	if der.len != p384_spki_prefix.len + p384_point_size {
		return error('expected a ${p384_spki_prefix.len + p384_point_size}-byte P-384 SubjectPublicKeyInfo, got ${der.len} bytes')
	}
	if der[..p384_spki_prefix.len] != p384_spki_prefix {
		return error('not a P-384 SubjectPublicKeyInfo')
	}
	return ecdsa.PublicKey.from_uncompressed_bytes(der[p384_spki_prefix.len..], nid: .secp384r1)!
}

// derive_shared_secret runs ECDH against the client public key (a base64 SPKI
// DER string from the login chain) and returns the 48-byte raw shared secret.
// A client key on the wrong curve is rejected while parsing, before the derive.
pub fn (k &ServerKeyPair) derive_shared_secret(client_public_key_b64 string) ![]u8 {
	der := base64.decode(client_public_key_b64)
	if der.len == 0 {
		return error('client public key is empty or not valid base64')
	}
	peer := p384_public_key_from_spki(der) or {
		return error('failed to parse client public key DER: ${err}')
	}
	defer {
		peer.free()
	}
	return k.private_key.derive_shared_secret(peer)!
}

// sign_es384 signs the message with the server private key using ECDSA-SHA384
// and returns the JWS-style fixed width raw R||S signature (96 bytes).
pub fn (k &ServerKeyPair) sign_es384(message []u8) ![]u8 {
	return der_ecdsa_to_raw(k.private_key.sign(message)!, p384_component_size)!
}

// der_ecdsa_to_raw converts a DER-encoded ECDSA signature (SEQUENCE of two
// INTEGERs r,s) into the fixed-width raw R||S form used by JWS/JWA. Each
// component is left-padded to comp_size bytes.
fn der_ecdsa_to_raw(der []u8, comp_size int) ![]u8 {
	mut i := 0
	if i >= der.len || der[i] != 0x30 {
		return error('invalid DER signature: missing SEQUENCE')
	}
	i++
	if i >= der.len {
		return error('invalid DER signature: truncated')
	}
	// Skip the SEQUENCE length (short or long form).
	if der[i] & 0x80 != 0 {
		i += int(der[i] & 0x7f) + 1
	} else {
		i++
	}
	r, next := read_der_integer(der, i)!
	s, _ := read_der_integer(der, next)!
	if r.len > comp_size || s.len > comp_size {
		return error('DER integer larger than component size')
	}
	mut out := []u8{len: comp_size * 2}
	copy(mut out[comp_size - r.len..comp_size], r)
	copy(mut out[comp_size * 2 - s.len..], s)
	return out
}

// read_der_integer reads one DER INTEGER starting at pos and returns the
// magnitude (with any leading sign/zero byte stripped) and the index just past
// the integer.
fn read_der_integer(der []u8, pos int) !([]u8, int) {
	mut i := pos
	if i >= der.len || der[i] != 0x02 {
		return error('invalid DER signature: expected INTEGER')
	}
	i++
	if i >= der.len {
		return error('invalid DER signature: truncated INTEGER length')
	}
	length := int(der[i])
	i++
	if length <= 0 || i + length > der.len {
		return error('invalid DER signature: bad INTEGER length')
	}
	value := der[i..i + length]
	i += length
	// Strip leading 0x00 that DER adds to keep the integer positive.
	mut start := 0
	for start < value.len - 1 && value[start] == 0 {
		start++
	}
	return value[start..].clone(), i
}
