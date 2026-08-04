// Thin forwarding wrappers around two OpenSSL EVP/X509 functions that vlib's
// crypto.ecdsa also declares, with narrower parameter types
// (EVP_DigestSign's tbslen as i32 instead of size_t, d2i_PUBKEY's length as
// u32 instead of long).
#include <openssl/evp.h>
#include <openssl/x509.h>

int vedrock_evp_digest_sign(EVP_MD_CTX *ctx, unsigned char *sig, size_t *siglen,
	const unsigned char *tbs, size_t tbslen) {
	return EVP_DigestSign(ctx, sig, siglen, tbs, tbslen);
}

EVP_PKEY *vedrock_d2i_pubkey(EVP_PKEY **a, const unsigned char **pp, long length) {
	return d2i_PUBKEY(a, pp, length);
}
