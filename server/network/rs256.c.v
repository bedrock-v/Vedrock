module network

import crypto.sha256
import net.mbedtls

// net.mbedtls links mbedTLS and owns its include path. Declaring its objects
// here as well would have to mirror its whole list. That's why only the functions used
// are declared.
#include <mbedtls/rsa.h>

@[typedef]
struct C.mbedtls_rsa_context {}

fn C.mbedtls_rsa_init(ctx &C.mbedtls_rsa_context)
fn C.mbedtls_rsa_free(ctx &C.mbedtls_rsa_context)
fn C.mbedtls_rsa_import_raw(ctx &C.mbedtls_rsa_context, n &u8, n_len usize, p &u8, p_len usize, q &u8, q_len usize, d &u8, d_len usize, e &u8, e_len usize) int
fn C.mbedtls_rsa_complete(ctx &C.mbedtls_rsa_context) int
fn C.mbedtls_rsa_check_pubkey(ctx &C.mbedtls_rsa_context) int
fn C.mbedtls_rsa_get_len(ctx &C.mbedtls_rsa_context) usize
fn C.mbedtls_rsa_pkcs1_verify(ctx &C.mbedtls_rsa_context, md_alg int, hashlen u32, hash &u8, sig &u8) int

// min_rsa_bytes is the smallest modulus accepted, 2048 bits.
const min_rsa_bytes = 256

// verify_rs256 checks a JWT's RS256 signature over message against the public
// key given by its big-endian modulus and exponent.
//
// RS256 is RSASSA-PKCS1-v1_5 with SHA-256 (RFC 7518 §3.3): the signer hashes the
// message, pads the hash in a fixed layout and signs that with its RSA private
// key. Verifying undoes the RSA step with the public key and compares the result
// with the padded hash of the message (RFC 8017 §8.2). mbedTLS checks the
// padding and the hash exactly.
fn verify_rs256(modulus []u8, exponent []u8, message []u8, signature []u8) ! {
	mut ctx := C.mbedtls_rsa_context{}
	C.mbedtls_rsa_init(&ctx)
	defer {
		C.mbedtls_rsa_free(&ctx)
	}
	if C.mbedtls_rsa_import_raw(&ctx, modulus.data, usize(modulus.len), unsafe { nil },
		0, unsafe { nil }, 0, unsafe { nil }, 0, exponent.data, usize(exponent.len)) != 0
		|| C.mbedtls_rsa_complete(&ctx) != 0 || C.mbedtls_rsa_check_pubkey(&ctx) != 0 {
		return error('not a valid RSA public key')
	}
	size := int(C.mbedtls_rsa_get_len(&ctx))
	if size < min_rsa_bytes {
		return error('RSA key of ${size * 8} bits is too small')
	}
	if signature.len != size {
		return error('signature of ${signature.len} bytes for a ${size} byte key')
	}
	digest := sha256.sum(message)
	if C.mbedtls_rsa_pkcs1_verify(&ctx, int(mbedtls.MbedtlsMdType.sha256), u32(digest.len),
		digest.data, signature.data) != 0 {
		return error('signature does not verify')
	}
}
