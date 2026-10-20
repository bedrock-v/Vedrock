module network

import encoding.base64
import sync
import bedrock_v.nethernet
import server.internal.auth

// IdentityTokenVerifier checks the token in a NetherNet identity assertion
// against Microsoft's published signing keys.
//
// It is the same token the Login packet carries later, issued by the same
// service for the same audience, so the check is the one the login path already
// makes. Making it here moves the decision earlier: an offer from
// somebody who cannot present a genuine token is refused before a peer
// connection is built for them.
//
// The verifier underneath caches what it discovered, so the lock is held across
// the call rather than around a copy: a handful of concurrent joins waiting on
// one key fetch is better than several of them racing the same request.
@[heap]
pub struct IdentityTokenVerifier {
mut:
	verifier auth.Verifier
	mutex    &sync.Mutex = sync.new_mutex()
}

pub fn new_identity_token_verifier(verifier auth.Verifier) &IdentityTokenVerifier {
	return &IdentityTokenVerifier{
		verifier: verifier
		mutex:    sync.new_mutex()
	}
}

// verify_token implements nethernet.TokenVerifier.
pub fn (mut v IdentityTokenVerifier) verify_token(token string) ! {
	v.mutex.lock()
	defer {
		v.mutex.unlock()
	}
	v.verifier.verify(token)!
}

// identity_key_matches reports whether the key a login chain is signed with is
// the one the transport was opened under.
//
// On RakNet the encryption handshake did this by itself: the session key came
// out of an exchange against the chain's key, so only its holder could read
// what followed. NetherNet runs inside DTLS and skips that handshake, which
// leaves the chain unbound, and an unbound chain is replayable by anyone who
// captured one somewhere else. The signalling assertion is what binds it,
// because the peer proved it holds the key the assertion names before the
// transport was accepted.
pub fn identity_key_matches(transport_key string, chain_key string) bool {
	if transport_key == '' || chain_key == '' {
		return false
	}
	// Compared as bytes rather than text: the same key can be written with or
	// without padding, and a difference there is not a different key.
	transport_der := base64.decode(transport_key)
	chain_der := base64.decode(chain_key)
	if transport_der.len == 0 || chain_der.len == 0 {
		return false
	}
	return transport_der == chain_der
}

// transport_identity_key is the peer's key as it appears in a login chain: the
// base64 SubjectPublicKeyInfo both sides of the comparison are written in.
pub fn transport_identity_key(conn &nethernet.Conn) string {
	public_key := conn.public_key() or { return '' }
	return nethernet.encode_public_key_base64(public_key) or { '' }
}
