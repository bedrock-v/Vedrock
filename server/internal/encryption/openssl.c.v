module encryption

// OpenSSL EVP interop for the Bedrock encryption handshake. vlib's crypto.ecdsa
// keeps its EVP_PKEY handle private, so we re-declare the C bindings we need
// (ECDH derive, SPKI emit, ES384 sign) in the same C-interop style. See
// vlib/crypto/ecdsa/ecdsa.c.v for the pattern this mirrors.

#flag darwin -L/opt/homebrew/opt/openssl/lib
#flag darwin -I/opt/homebrew/opt/openssl/include
#flag darwin -I/usr/local/opt/openssl/include
#flag darwin -L/usr/local/opt/openssl/lib

#flag linux -I/usr/local/include/openssl
#flag linux -L/usr/local/lib64/

#flag -I/usr/include/openssl
#flag -lcrypto

#include <openssl/evp.h>
#include <openssl/ec.h>
#include <openssl/x509.h>
#include <openssl/bio.h>
#include <openssl/obj_mac.h>

@[typedef]
pub struct C.EVP_PKEY {}

@[typedef]
pub struct C.EVP_PKEY_CTX {}

@[typedef]
pub struct C.EVP_MD_CTX {}

@[typedef]
pub struct C.EVP_MD {}

@[typedef]
pub struct C.BIO {}

@[typedef]
pub struct C.BIO_METHOD {}

fn C.EVP_PKEY_new() &C.EVP_PKEY
fn C.EVP_PKEY_free(key &C.EVP_PKEY)

fn C.EVP_PKEY_CTX_new(pkey &C.EVP_PKEY, e voidptr) &C.EVP_PKEY_CTX
fn C.EVP_PKEY_CTX_new_id(id int, e voidptr) &C.EVP_PKEY_CTX
fn C.EVP_PKEY_CTX_free(ctx &C.EVP_PKEY_CTX)

fn C.EVP_PKEY_keygen_init(ctx &C.EVP_PKEY_CTX) int
fn C.EVP_PKEY_keygen(ctx &C.EVP_PKEY_CTX, ppkey &&C.EVP_PKEY) int
fn C.EVP_PKEY_CTX_set_ec_paramgen_curve_nid(ctx &C.EVP_PKEY_CTX, nid int) int

fn C.EVP_PKEY_derive_init(ctx &C.EVP_PKEY_CTX) int
fn C.EVP_PKEY_derive_set_peer(ctx &C.EVP_PKEY_CTX, peer &C.EVP_PKEY) int
fn C.EVP_PKEY_derive(ctx &C.EVP_PKEY_CTX, key &u8, keylen &usize) int

fn C.EVP_DigestSignInit(ctx &C.EVP_MD_CTX, pctx &&C.EVP_PKEY_CTX, tipe &C.EVP_MD, e voidptr, pkey &C.EVP_PKEY) int
fn C.EVP_DigestSign(ctx &C.EVP_MD_CTX, sig &u8, siglen &usize, tbs &u8, tbslen usize) int
fn C.EVP_MD_CTX_new() &C.EVP_MD_CTX
fn C.EVP_MD_CTX_free(ctx &C.EVP_MD_CTX)
fn C.EVP_sha384() &C.EVP_MD

fn C.BIO_new(t &C.BIO_METHOD) &C.BIO
fn C.BIO_s_mem() &C.BIO_METHOD
fn C.BIO_free_all(a &C.BIO)
fn C.BIO_write(b &C.BIO, buf &u8, length int) int
fn C.i2d_PUBKEY_bio(bo &C.BIO, pkey &C.EVP_PKEY) int
fn C.BIO_ctrl(b &C.BIO, cmd int, larg i64, parg voidptr) i64
fn C.d2i_PUBKEY(k &&C.EVP_PKEY, pp &&u8, length i64) &C.EVP_PKEY

const nid_secp384r1 = C.NID_secp384r1
const evp_pkey_ec = C.EVP_PKEY_EC
const bio_ctrl_info = 3 // BIO_CTRL_INFO - returns the in-memory buffer pointer
