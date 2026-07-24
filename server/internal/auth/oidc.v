module auth

import net.http
import x.json2
import sync
import time

// A client signed into Xbox Live sends a single OpenID identity token under
// a "Token" field, instead of the legacy certificate chain verify_chain
// handles (see parse_identity_token). That token is signed by Microsoft
// with RS256 keys that rotate, so there's no fixed key to pin. Verifying it
// means two lookups: service discovery for the current auth issuer, then
// that issuer's own OpenID discovery document for its JWKS endpoint. Same
// approach gophertunnel's minecraft/service package uses.

const discovery_url = 'https://client.discovery.minecraft-services.net/api/v1.0/discovery/MinecraftPE/builds/1.26.30'

// expected_audience is the fixed identifier Microsoft issues Bedrock login
// tokens for. A server can't discover this value, it's a constant.
const expected_audience = 'api://auth-minecraft-services/multiplayer'

// clock_skew_secs tolerates minor clock drift between this server and
// Microsoft's token issuance time when checking exp/nbf.
const clock_skew_secs = i64(120)

const jwks_refresh_interval_secs = i64(30 * 60)

struct JwksKey {
	kid string
	n   string
	e   string
}

// OidcVerifier discovers Microsoft's OpenID configuration and checks login
// tokens against its published signing keys. Build one and reuse it for
// the whole process (Hub owns one). It fetches nothing until the first
// real login, so server startup never depends on the network being up,
// and discovery and keys are cached afterward so later logins are free
// unless a key rotation forces a refresh.
@[heap]
pub struct OidcVerifier {
mut:
	mutex          &sync.Mutex = sync.new_mutex()
	issuer         string
	jwks_uri       string
	discovered     bool
	keys           []JwksKey
	last_key_fetch i64
}

pub fn new_oidc_verifier() &OidcVerifier {
	return &OidcVerifier{
		mutex: sync.new_mutex()
	}
}

struct OidcConfig {
	jwks_uri string
}

fn fetch_auth_issuer() !string {
	resp := http.get(discovery_url)!
	if resp.status_code != 200 {
		return error('discovery request failed with status ${resp.status_code}')
	}
	root := json2.decode[json2.Any](resp.body)!.as_map()
	result := (root['result'] or { return error('discovery response missing result') }).as_map()
	environments := (result['serviceEnvironments'] or {
		return error('discovery response missing serviceEnvironments')
	}).as_map()
	auth_env :=
		(environments['auth'] or { return error('discovery response missing auth service') }).as_map()
	prod := (auth_env['prod'] or {
		return error('discovery response missing auth prod environment')
	}).as_map()
	issuer := (prod['issuer'] or { return error('auth prod environment missing issuer') }).str()
	if issuer == '' {
		return error('auth prod environment issuer is empty')
	}
	return issuer
}

fn fetch_oidc_config(issuer string) !OidcConfig {
	url := issuer.trim_right('/') + '/.well-known/openid-configuration'
	resp := http.get(url)!
	if resp.status_code != 200 {
		return error('openid-configuration request failed with status ${resp.status_code}')
	}
	root := json2.decode[json2.Any](resp.body)!.as_map()
	jwks_uri :=
		(root['jwks_uri'] or { return error('openid-configuration missing jwks_uri') }).str()
	if jwks_uri == '' {
		return error('openid-configuration jwks_uri is empty')
	}
	return OidcConfig{
		jwks_uri: jwks_uri
	}
}

fn fetch_jwks(jwks_uri string) ![]JwksKey {
	resp := http.get(jwks_uri)!
	if resp.status_code != 200 {
		return error('jwks request failed with status ${resp.status_code}')
	}
	root := json2.decode[json2.Any](resp.body)!.as_map()
	entries := (root['keys'] or { return error('jwks response missing keys') }).as_array()
	mut out := []JwksKey{cap: entries.len}
	for entry in entries {
		key := entry.as_map()
		kty := (key['kty'] or { json2.Any('') }).str()
		if kty != 'RSA' {
			continue
		}
		kid := (key['kid'] or { json2.Any('') }).str()
		n := (key['n'] or { json2.Any('') }).str()
		e := (key['e'] or { json2.Any('') }).str()
		if kid == '' || n == '' || e == '' {
			continue
		}
		out << JwksKey{
			kid: kid
			n:   n
			e:   e
		}
	}
	return out
}

// ensure_discovered looks up the issuer and jwks_uri once per process.
// The lock stays held across the network calls on purpose: a few
// concurrent first logins waiting on one discovery round trip is a better
// trade than letting several threads race duplicate requests.
fn (mut v OidcVerifier) ensure_discovered() ! {
	v.mutex.lock()
	defer {
		v.mutex.unlock()
	}
	if v.discovered {
		return
	}
	issuer := fetch_auth_issuer()!
	config := fetch_oidc_config(issuer)!
	v.issuer = issuer
	v.jwks_uri = config.jwks_uri
	v.discovered = true
}

// key_for_kid returns the signing key for kid, refreshing the cached JWKS
// if it isn't recognised. This covers both the first lookup and a real key
// rotation, but never more often than jwks_refresh_interval_secs, so a
// client sending garbage kids can't force endless refetching.
fn (mut v OidcVerifier) key_for_kid(kid string) !JwksKey {
	v.ensure_discovered()!

	v.mutex.lock()
	cached := v.keys.clone()
	last_fetch := v.last_key_fetch
	jwks_uri := v.jwks_uri
	v.mutex.unlock()

	for k in cached {
		if k.kid == kid {
			return k
		}
	}

	now := time.now().unix()
	if cached.len > 0 && now - last_fetch < jwks_refresh_interval_secs {
		return error('no signing key found for kid ${kid}')
	}

	fetched := fetch_jwks(jwks_uri)!
	v.mutex.lock()
	v.keys = fetched
	v.last_key_fetch = now
	v.mutex.unlock()

	for k in fetched {
		if k.kid == kid {
			return k
		}
	}
	return error('no signing key found for kid ${kid}')
}

fn audience_matches(payload map[string]json2.Any) bool {
	aud := payload['aud'] or { return false }
	if aud is string {
		return aud == expected_audience
	}
	if aud is []json2.Any {
		for entry in aud {
			if entry.str() == expected_audience {
				return true
			}
		}
	}
	return false
}

// validate_oidc_claims checks iss, aud, exp and nbf against a payload
// whose signature is already verified. Kept separate from verify() so it
// can be tested against synthetic payloads without a real network call or
// signature (rsa_verify_test.v covers the crypto side).
fn validate_oidc_claims(payload map[string]json2.Any, expected_issuer string) ! {
	iss := map_string(payload, 'iss')
	if iss.trim_right('/') != expected_issuer.trim_right('/') {
		return error('unexpected token issuer ${iss}')
	}
	if !audience_matches(payload) {
		return error('unexpected token audience')
	}
	now := time.now().unix()
	exp_claim := payload['exp'] or { return error('token missing exp claim') }
	if now > i64(exp_claim.f64()) + clock_skew_secs {
		return error('token has expired')
	}
	if nbf_claim := payload['nbf'] {
		if now < i64(nbf_claim.f64()) - clock_skew_secs {
			return error('token is not yet valid')
		}
	}
}

// verify checks token's signature against the discovered JWKS and
// validates iss, aud, exp and nbf, returning the payload only for a
// genuine, current Microsoft token issued for this audience. Any failure
// (unknown kid, bad signature, wrong issuer or audience, expired token) is
// a plain error. Callers treat every error the same as not authenticated.
pub fn (mut v OidcVerifier) verify(token string) !map[string]json2.Any {
	jwt := decode_jwt(token)!
	alg := (jwt.header['alg'] or { json2.Any('') }).str()
	if alg != 'RS256' {
		return error('unsupported token signing algorithm ${alg}')
	}
	kid := (jwt.header['kid'] or { return error('token header missing kid') }).str()
	if kid == '' {
		return error('token header missing kid')
	}

	key := v.key_for_kid(kid)!
	if !verify_jwt_rs256(token, key.n, key.e)! {
		return error('token signature verification failed')
	}

	v.mutex.lock()
	issuer := v.issuer
	v.mutex.unlock()

	validate_oidc_claims(jwt.payload, issuer)!
	return jwt.payload
}
