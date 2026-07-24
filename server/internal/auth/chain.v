module auth

import x.json2

pub const mojang_public_key = 'MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAECRXueJeTDqNRRgJi/vlRufByu/2G0i2Ebt6YMar5QX/R0DIIyrJMcUpruK4QveTfJSTp3Shlq4Gk34cD/4GUWwkv0DVuzeuB+tXija7HBxii03NHDbPAD0AKnLr2wdAp'

pub struct Identity {
pub:
	xuid               string
	uuid               string
	display_name       string
	xbox_authenticated bool
	client_public_key  string
}

// parse_login_chain verifies the JWT signature chain and returns the client
// identity. A self-signed (offline mode) chain has valid signatures that
// prove nothing about who the player really is. xbox_authenticated is only
// true when the chain roots in Mojang's public key, or the token is a
// genuine, current OpenID token issued by Microsoft for this audience (see
// parse_identity_token). Treat display_name and xuid as unverified unless
// xbox_authenticated is true.
pub fn parse_login_chain(auth_info_json string, require_xbox bool, mut verifier OidcVerifier) !Identity {
	root := json2.decode[json2.Any](auth_info_json)!.as_map()
	chain := extract_chain(root)!
	mut identity := Identity{}
	if chain.len > 0 {
		identity = verify_chain(chain)!
	} else if 'Token' in root && (root['Token'] or { json2.Any('') }).str() != '' {
		identity = parse_identity_token(mut verifier, (root['Token'] or { json2.Any('') }).str())!
	} else {
		return error('login request contained no certificate chain or identity token')
	}
	if require_xbox && !identity.xbox_authenticated {
		return error('player is not authenticated with Xbox Live')
	}
	return identity
}

// parse_identity_token handles a real client's single token login:
// {"AuthenticationType": ..., "Token": "<jwt>"}. The token is an OpenID ID
// token issued by Microsoft, signed with RS256 keys that rotate, so there
// is no fixed key to pin the way the legacy chain pins mojang_public_key.
// xbox_authenticated means OidcVerifier.verify checked the signature
// against Microsoft's current published keys and validated the issuer,
// audience and expiry. A present xid claim proves nothing by itself, since
// the client controls it.
fn parse_identity_token(mut verifier OidcVerifier, token string) !Identity {
	unverified := decode_jwt(token)!.payload
	xuid := map_string(unverified, 'xid')
	mut authenticated := false
	if xuid != '' {
		if _ := verifier.verify(token) {
			authenticated = true
		}
	}
	mut uuid := map_string(unverified, 'identity')
	if uuid == '' {
		uuid = map_string(unverified, 'sub')
	}
	return Identity{
		xuid:               xuid
		uuid:               uuid
		display_name:       map_string(unverified, 'xname')
		xbox_authenticated: authenticated
		client_public_key:  map_string(unverified, 'cpk')
	}
}

fn extract_chain(root map[string]json2.Any) ![]string {
	if 'chain' in root {
		return to_string_array(root['chain'] or { json2.Any('') })
	}
	if 'Certificate' in root {
		raw := (root['Certificate'] or { json2.Any('') }).str()
		if raw != '' {
			certificate := json2.decode[json2.Any](raw)!.as_map()
			if 'chain' in certificate {
				return to_string_array(certificate['chain'] or { json2.Any('') })
			}
		}
	}
	return []string{}
}

fn to_string_array(value json2.Any) []string {
	mut result := []string{}
	for entry in value.as_array() {
		result << entry.str()
	}
	return result
}

// is_trusted_key reports whether a token verified with this key roots the
// chain in Mojang's authority. Only the pinned Mojang public key counts as
// trusted. This anchor must never come from a payload field the client
// controls.
fn is_trusted_key(current_key string) bool {
	return current_key == mojang_public_key
}

// verify_chain walks the login chain in order, tracking the key that
// verifies the current token. Token 0 is checked against its own x5u
// header; every later token is checked against the identityPublicKey the
// previous token carried. A chain counts as Xbox authenticated only when
// some token was actually verified with the Mojang public key, never
// because a payload field claims to be Mojang's.
fn verify_chain(chain []string) !Identity {
	first := decode_jwt(chain[0])!
	if 'x5u' !in first.header {
		return error('first chain token is missing x5u header')
	}
	mut current_key := (first.header['x5u'] or { json2.Any('') }).str()
	mut authenticated := false
	mut client_key := ''
	mut extra := map[string]json2.Any{}
	for i, token in chain {
		if !verify_jwt(token, current_key)! {
			return error('signature verification failed for chain token ${i}')
		}
		if is_trusted_key(current_key) {
			authenticated = true
		}
		payload := decode_jwt(token)!.payload
		if 'identityPublicKey' in payload {
			next_key := (payload['identityPublicKey'] or { json2.Any('') }).str()
			client_key = next_key
			current_key = next_key
		}
		if 'extraData' in payload {
			extra = (payload['extraData'] or { json2.Any('') }).as_map()
		}
	}
	return Identity{
		xuid:               map_string(extra, 'XUID')
		uuid:               map_string(extra, 'identity')
		display_name:       map_string(extra, 'displayName')
		xbox_authenticated: authenticated
		client_public_key:  client_key
	}
}

fn map_string(values map[string]json2.Any, key string) string {
	if key in values {
		return (values[key] or { json2.Any('') }).str()
	}
	return ''
}
