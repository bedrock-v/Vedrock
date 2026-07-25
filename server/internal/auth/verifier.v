module auth

import x.json2

// Verifier validates a single-token OpenID login. OidcVerifier is the
// default implementation; embedders may provide a custom verifier for
// testing or custom token-validation policies.
pub interface Verifier {
mut:
	verify(token string) !map[string]json2.Any
}
