module network

import encoding.base64
import net.http
import sync
import time
import x.json2
import bedrock_v.protocol

// multiplayer_audience is the audience Minecraft's authorization service issues
// login tokens for.
const multiplayer_audience = 'api://auth-minecraft-services/multiplayer'

// token_leeway is how far clocks may disagree when a token's times are checked.
const token_leeway = i64(60)

// LoginVerifier checks the token a client logs in with and returns its claims.
// OidcVerifier checks it against Minecraft's authorization service. A test or an
// offline server can supply its own.
pub interface LoginVerifier {
mut:
	verify(token string) !map[string]json2.Any
}

@[params]
pub struct OidcVerifierConfig {
pub:
	discovery_url string = 'https://client.discovery.minecraft-services.net/api/v1.0/discovery/MinecraftPE/builds/${protocol.minecraft_version}'
	refresh_interval time.Duration = 30 * time.minute
	min_forced_refresh time.Duration = time.minute
	// http_timeout bounds each request to the authorization service.
	http_timeout time.Duration = 10 * time.second
}

struct RsaKey {
	modulus  []u8
	exponent []u8
}

// OidcVerifier verifies login tokens issued by Minecraft's authorization service:
// RS256 signatures against the service's published keys, the issuer, the
// audience and the token's times.
//
// It finds the service through Minecraft's discovery document. Keys are fetched
// when it is built, again every refresh_interval and when a token names a key it
// doesn't know. A failed refresh keeps the keys it had.
@[heap]
pub struct OidcVerifier {
	cfg OidcVerifierConfig
mut:
	// mu guards issuer, keys and refreshed_at.
	mu           &sync.Mutex = sync.new_mutex()
	issuer       string
	keys         map[string]RsaKey
	refreshed_at time.Time
	// refreshing lets one refresh run at a time.
	refreshing &sync.Mutex = sync.new_mutex()
	done       chan bool   = chan bool{}
	closed     bool
	refresher  thread
}

// OidcVerifier.new fetches the authorization service's issuer and keys and fails
// when it can't. It refreshes them on its own thread until it is closed.
pub fn OidcVerifier.new(cfg OidcVerifierConfig) !&OidcVerifier {
	mut v := &OidcVerifier{
		cfg: cfg
	}
	v.refresh(0)!
	v.refresher = spawn v.refresh_loop()
	return v
}

// close stops the refreshes and waits for the thread doing them.
pub fn (mut v OidcVerifier) close() {
	v.mu.lock()
	if v.closed {
		v.mu.unlock()
		return
	}
	v.closed = true
	v.done.close()
	v.mu.unlock()
	v.refresher.wait()
}

// verify returns the claims of a token the authorization service signed for
// this audience and that is within its times. Anything else is an error.
pub fn (mut v OidcVerifier) verify(token string) !map[string]json2.Any {
	parts := token.split('.')
	if parts.len != 3 {
		return error('login token is not a JWT')
	}
	header := decode_jwt_part(parts[0])!
	alg := field(header, 'alg')
	if alg != 'RS256' {
		return error('login token is signed with "${alg}", only RS256 is accepted')
	}
	kid := field(header, 'kid')
	if kid == '' {
		return error('login token names no signing key')
	}
	key := v.key(kid)!
	verify_rs256(key.modulus, key.exponent, '${parts[0]}.${parts[1]}'.bytes(), base64.url_decode(parts[2]))!
	claims := decode_jwt_part(parts[1])!
	v.mu.lock()
	issuer := v.issuer
	v.mu.unlock()
	check_claims(claims, issuer, time.now().unix())!
	return claims
}

// key returns the signing key a token names, refreshing the keys once when it
// isn't among them.
fn (mut v OidcVerifier) key(kid string) !RsaKey {
	v.mu.lock()
	if key := v.keys[kid] {
		v.mu.unlock()
		return key
	}
	v.mu.unlock()
	v.refresh(v.cfg.min_forced_refresh)!
	v.mu.lock()
	defer {
		v.mu.unlock()
	}
	return v.keys[kid] or { error('login token names an unknown signing key "${kid}"') }
}

fn (mut v OidcVerifier) refresh_loop() {
	interval := v.cfg.refresh_interval
	for {
		select {
			_ := <-v.done {
				return
			}
			interval {
				v.refresh(0) or {
					// TODO Yeah again... you know, we should add a real logger :D
					eprintln('vedrock: refreshing the login signing keys failed, keeping the ones there are: ${err}')
				}
			}
		}
	}
}

// refresh fetches the issuer and the keys again unless they were fetched less
// than since ago. A refresh that fails changes nothing.
fn (mut v OidcVerifier) refresh(since time.Duration) ! {
	v.refreshing.lock()
	defer {
		v.refreshing.unlock()
	}
	v.mu.lock()
	recent := since > 0 && time.since(v.refreshed_at) < since
	v.mu.unlock()
	if recent {
		return
	}

	discovered := discovered_issuer(v.get_json(v.cfg.discovery_url)!)!
	configuration := v.get_json('${discovered.trim_right('/')}/.well-known/openid-configuration')!
	issuer := field(configuration, 'issuer')
	if issuer.trim_right('/') != discovered.trim_right('/') {
		return error('the OpenID configuration names issuer "${issuer}", discovery named "${discovered}"')
	}
	algs := (configuration['id_token_signing_alg_values_supported'] or { json2.Any('') }).as_array()
	if !algs.any(it.str() == 'RS256') {
		return error('the authorization service does not sign with RS256')
	}
	jwks_uri := field(configuration, 'jwks_uri')
	if !jwks_uri.starts_with('https://') {
		return error('the signing keys are not served over https: "${jwks_uri}"')
	}
	keys := parse_jwks(v.get_json(jwks_uri)!)!

	v.mu.lock()
	v.issuer = issuer
	v.keys = keys.clone()
	v.refreshed_at = time.now()
	v.mu.unlock()
}

fn (v &OidcVerifier) get_json(url string) !map[string]json2.Any {
	timeout := i64(v.cfg.http_timeout)
	response := http.fetch(url: url, read_timeout: timeout, write_timeout: timeout) or {
		return error('GET ${url}: ${err}')
	}
	if response.status_code != 200 {
		return error('GET ${url}: status ${response.status_code}')
	}
	return json2.decode[json2.Any](response.body)!.as_map()
}

// discovered_issuer reads the authorization service's issuer out of Minecraft's
// discovery document.
fn discovered_issuer(document map[string]json2.Any) !string {
	result := (document['result'] or { return error('discovery has no result') }).as_map()
	services := (result['serviceEnvironments'] or {
		return error('discovery lists no services')
	}).as_map()
	auth := (services['auth'] or { return error('discovery lists no auth service') }).as_map()
	prod := (auth['prod'] or { return error('discovery lists no prod auth environment') }).as_map()
	issuer := field(prod, 'issuer')
	if !issuer.starts_with('https://') {
		return error('discovery names no https issuer: "${issuer}"')
	}
	return issuer
}

// parse_jwks reads the RSA signing keys out of a JSON Web Key Set by key id.
// Keys for anything but RS256 signatures are left out.
fn parse_jwks(document map[string]json2.Any) !map[string]RsaKey {
	mut keys := map[string]RsaKey{}
	for entry in (document['keys'] or { return error('the key set has no keys') }).as_array() {
		key := entry.as_map()
		if field(key, 'kty') != 'RSA' || field(key, 'use') !in ['', 'sig']
			|| field(key, 'alg') !in ['', 'RS256'] {
			continue
		}
		kid := field(key, 'kid')
		modulus := base64.url_decode(field(key, 'n'))
		exponent := base64.url_decode(field(key, 'e'))
		if kid == '' || modulus.len == 0 || exponent.len == 0 {
			continue
		}
		keys[kid] = RsaKey{
			modulus:  modulus
			exponent: exponent
		}
	}
	if keys.len == 0 {
		return error('the key set has no RSA signing keys')
	}
	return keys
}

// check_claims checks that a token is from issuer, for this audience and within
// its times at now, in seconds since the Unix epoch. An expiry is required.
fn check_claims(claims map[string]json2.Any, issuer string, now i64) ! {
	if field(claims, 'iss') != issuer {
		return error('login token is from "${field(claims, 'iss')}", not "${issuer}"')
	}
	aud := claims['aud'] or { return error('login token names no audience') }
	audiences := if aud is []json2.Any { aud.map(it.str()) } else { [aud.str()] }
	if multiplayer_audience !in audiences {
		return error('login token is not for "${multiplayer_audience}"')
	}
	exp := claims['exp'] or { return error('login token has no expiry') }
	if now > exp.i64() + token_leeway {
		return error('login token expired at ${exp.i64()}')
	}
	if nbf := claims['nbf'] {
		if now + token_leeway < nbf.i64() {
			return error('login token is not valid before ${nbf.i64()}')
		}
	}
	if iat := claims['iat'] {
		if iat.i64() > now + token_leeway {
			return error('login token was issued at ${iat.i64()}, in the future')
		}
	}
}

fn decode_jwt_part(part string) !map[string]json2.Any {
	return json2.decode[json2.Any](base64.url_decode(part).bytestr())!.as_map()
}
