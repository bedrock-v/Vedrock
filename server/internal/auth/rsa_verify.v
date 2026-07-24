module auth

import math.big
import crypto.sha256

// sha256_digest_info is the fixed DER prefix RFC 8017 (PKCS#1 v1.5,
// appendix A.2.4) specifies for a SHA-256 DigestInfo, followed by the
// 32 byte hash itself. Every valid RSA SHA-256 signature uses this prefix.
const sha256_digest_info = [u8(0x30), 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65,
	0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20]

// rsa_public_key holds a modulus/exponent pair decoded from a JWK's base64url
// "n"/"e" fields.
struct RsaPublicKey {
	n big.Integer
	k int // byte length of the modulus, the width every PKCS#1 v1.5 block must fill
}

fn rsa_public_key_from_b64url(n_b64url string, e_b64url string) !(RsaPublicKey, u64) {
	n_bytes := b64url_decode(n_b64url)!
	e_bytes := b64url_decode(e_b64url)!
	n := big.integer_from_bytes(n_bytes)
	mut e := u64(0)
	for b in e_bytes {
		e = (e << 8) | u64(b)
	}
	if e == 0 {
		return error('RSA public exponent decoded to zero')
	}
	return RsaPublicKey{
		n: n
		k: n_bytes.len
	}, e
}

// rsa_left_pad pads value with leading zero bytes to exactly width bytes.
// big.Integer.bytes() drops leading zeros, but the encoded message must
// stay exactly k bytes wide (k is the modulus length). Without this, a
// decrypted value starting with a zero byte would shrink and every
// comparison after it would check the wrong offsets.
fn rsa_left_pad(value []u8, width int) []u8 {
	if value.len >= width {
		return value[value.len - width..].clone()
	}
	mut out := []u8{len: width - value.len, init: 0}
	out << value
	return out
}

// verify_rsa_pkcs1_sha256 checks an RS256 signature against message, using
// the RSA public key described by n_b64url and e_b64url (a JWK's own "n"
// and "e" fields). Returns false, not an error, for a well formed but
// non-matching signature. Only a malformed key or signature is an error.
fn verify_rsa_pkcs1_sha256(message []u8, signature []u8, n_b64url string, e_b64url string) !bool {
	key, e := rsa_public_key_from_b64url(n_b64url, e_b64url)!
	if signature.len != key.k {
		// A correctly signed RS256 signature is always exactly as wide as
		// the modulus.
		return false
	}
	s := big.integer_from_bytes(signature)
	m := s.mod_pow(e, key.n)
	m_bytes, signum := m.bytes()
	if signum < 0 {
		return false
	}
	em := rsa_left_pad(m_bytes, key.k)

	hash := sha256.sum256(message)
	mut expected_t := []u8{}
	expected_t << sha256_digest_info
	expected_t << hash

	// RSA signature block layout:
	// 00 01, enough FF bytes to fill the block, 00, then the hash header and hash.
	if key.k < expected_t.len + 11 {
		return error('RSA modulus too small for a SHA-256 signature')
	}
	ps_len := key.k - expected_t.len - 3
	mut expected_em := []u8{cap: key.k}
	expected_em << u8(0x00)
	expected_em << u8(0x01)
	for _ in 0 .. ps_len {
		expected_em << u8(0xff)
	}
	expected_em << u8(0x00)
	expected_em << expected_t

	if em.len != expected_em.len {
		return false
	}
	for i in 0 .. em.len {
		if em[i] != expected_em[i] {
			return false
		}
	}
	return true
}

// verify_jwt_rs256 verifies a full "header.payload.signature" JWT string
// against an RSA public key described by its JWK "n" and "e" fields. Same
// shape as verify_jwt, which handles the ECDSA chain path.
fn verify_jwt_rs256(token string, n_b64url string, e_b64url string) !bool {
	parts := token.split('.')
	if parts.len != 3 {
		return error('invalid JWT format')
	}
	signing_input := '${parts[0]}.${parts[1]}'
	signature := b64url_decode(parts[2])!
	return verify_rsa_pkcs1_sha256(signing_input.bytes(), signature, n_b64url, e_b64url)
}
