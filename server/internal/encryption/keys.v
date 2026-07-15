module encryption

import encoding.base64

// ServerKeyPair holds the ephemeral P-384 ECDH/signing keypair the server
// generates once per session for the encryption handshake. It owns the raw
// EVP_PKEY handle and must be freed when the handshake is done.
pub struct ServerKeyPair {
mut:
	pkey &C.EVP_PKEY = unsafe { nil }
}

// new_server_key_pair generates a fresh secp384r1 keypair via OpenSSL EVP.
pub fn new_server_key_pair() !&ServerKeyPair {
	ctx := C.EVP_PKEY_CTX_new_id(evp_pkey_ec, unsafe { nil })
	if ctx == unsafe { nil } {
		return error('EVP_PKEY_CTX_new_id failed')
	}
	defer {
		C.EVP_PKEY_CTX_free(ctx)
	}
	if C.EVP_PKEY_keygen_init(ctx) != 1 {
		return error('EVP_PKEY_keygen_init failed')
	}
	if C.EVP_PKEY_CTX_set_ec_paramgen_curve_nid(ctx, nid_secp384r1) != 1 {
		return error('failed to set P-384 curve')
	}
	mut pkey := &C.EVP_PKEY(unsafe { nil })
	if C.EVP_PKEY_keygen(ctx, &pkey) != 1 {
		return error('EVP_PKEY_keygen failed')
	}
	return &ServerKeyPair{
		pkey: pkey
	}
}

// free releases the underlying EVP_PKEY. Safe to call once.
pub fn (mut k ServerKeyPair) free() {
	if k.pkey != unsafe { nil } {
		C.EVP_PKEY_free(k.pkey)
		k.pkey = unsafe { nil }
	}
}

// public_key_der returns the server's SubjectPublicKeyInfo (SPKI) DER bytes,
// used as the base64 x5u header of the ServerToClientHandshake JWT.
pub fn (k &ServerKeyPair) public_key_der() ![]u8 {
	bio := C.BIO_new(C.BIO_s_mem())
	if bio == unsafe { nil } {
		return error('BIO_new failed')
	}
	defer {
		C.BIO_free_all(bio)
	}
	if C.i2d_PUBKEY_bio(bio, k.pkey) != 1 {
		return error('i2d_PUBKEY_bio failed')
	}
	mut buf := &u8(unsafe { nil })
	length := C.BIO_ctrl(bio, bio_ctrl_info, 0, voidptr(&buf))
	if length <= 0 || buf == unsafe { nil } {
		return error('failed to read SPKI from BIO')
	}
	mut out := []u8{len: int(length)}
	unsafe { vmemcpy(out.data, buf, int(length)) }
	return out
}

// derive_shared_secret runs ECDH against the client public key (a base64 SPKI
// DER string from the login chain) and returns the 48-byte raw shared secret.
pub fn (k &ServerKeyPair) derive_shared_secret(client_public_key_b64 string) ![]u8 {
	der := base64.decode(client_public_key_b64)
	if der.len == 0 {
		return error('client public key is empty or not valid base64')
	}
	mut peer := &C.EVP_PKEY(unsafe { nil })
	pp := &u8(der.data)
	peer = C.d2i_PUBKEY(&peer, &pp, i64(der.len))
	if peer == unsafe { nil } {
		return error('failed to parse client public key DER')
	}
	defer {
		C.EVP_PKEY_free(peer)
	}
	ctx := C.EVP_PKEY_CTX_new(k.pkey, unsafe { nil })
	if ctx == unsafe { nil } {
		return error('EVP_PKEY_CTX_new failed')
	}
	defer {
		C.EVP_PKEY_CTX_free(ctx)
	}
	if C.EVP_PKEY_derive_init(ctx) != 1 {
		return error('EVP_PKEY_derive_init failed')
	}
	if C.EVP_PKEY_derive_set_peer(ctx, peer) != 1 {
		return error('EVP_PKEY_derive_set_peer failed (curve mismatch?)')
	}
	mut secret_len := usize(0)
	if C.EVP_PKEY_derive(ctx, unsafe { nil }, &secret_len) != 1 {
		return error('EVP_PKEY_derive length query failed')
	}
	if secret_len == 0 {
		return error('derived secret length is zero')
	}
	mut secret := []u8{len: int(secret_len)}
	if C.EVP_PKEY_derive(ctx, secret.data, &secret_len) != 1 {
		return error('EVP_PKEY_derive failed')
	}
	return secret[..int(secret_len)].clone()
}

// sign_es384 signs the message with the server private key using ECDSA-SHA384
// and returns the JWS-style fixed-width raw R||S signature (96 bytes for P-384).
pub fn (k &ServerKeyPair) sign_es384(message []u8) ![]u8 {
	md_ctx := C.EVP_MD_CTX_new()
	if md_ctx == unsafe { nil } {
		return error('EVP_MD_CTX_new failed')
	}
	defer {
		C.EVP_MD_CTX_free(md_ctx)
	}
	if C.EVP_DigestSignInit(md_ctx, unsafe { nil }, C.EVP_sha384(), unsafe { nil }, k.pkey) != 1 {
		return error('EVP_DigestSignInit failed')
	}
	mut sig_len := usize(0)
	if C.EVP_DigestSign(md_ctx, unsafe { nil }, &sig_len, message.data, usize(message.len)) != 1 {
		return error('EVP_DigestSign length query failed')
	}
	mut der_sig := []u8{len: int(sig_len)}
	if C.EVP_DigestSign(md_ctx, der_sig.data, &sig_len, message.data, usize(message.len)) != 1 {
		return error('EVP_DigestSign failed')
	}
	return der_ecdsa_to_raw(der_sig[..int(sig_len)], p384_component_size)!
}

const p384_component_size = 48

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
