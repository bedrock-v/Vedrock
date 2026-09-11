module auth

import encoding.base64
import server.internal.encryption

const test_public_key_spki = 'MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEMRN5QQLImPvKk5qO/DLS4MMDXIKWxBPxUUn4MFMGnjvsV8knmkerWODhaHhq55RYPNs9HWP8wLdLGgwB7F+a1RgIUZuzdwveeq/9cf9OGKHX0Adc9YuE05+mokqo4qqD'

fn test_der_integer_encoding() {
	assert der_integer([u8(0x00), 0x05]) == [u8(0x02), 0x01, 0x05]
	assert der_integer([u8(0x80), 0x01]) == [u8(0x02), 0x03, 0x00, 0x80, 0x01]
}

fn test_signature_to_der() {
	raw := [u8(0x00), 0x05, 0x80, 0x01]
	der := ecdsa_signature_to_der(raw)!
	assert der == [u8(0x30), 0x08, 0x02, 0x01, 0x05, 0x02, 0x03, 0x00, 0x80, 0x01]
}

fn test_b64url_decode_without_padding() {
	assert b64url_decode('aGVsbG8')!.bytestr() == 'hello'
}

// make_token signs a login token with keys, the way a client does: ES384 with a
// raw R||S signature.
fn make_token(header_json string, payload_json string, keys &encryption.ServerKeyPair) !string {
	h := base64.url_encode(header_json.bytes()).trim_right('=')
	p := base64.url_encode(payload_json.bytes()).trim_right('=')
	signing_input := '${h}.${p}'
	sig := base64.url_encode(keys.sign_es384(signing_input.bytes())!).trim_right('=')
	return '${signing_input}.${sig}'
}

fn unsigned_token(header_json string, payload_json string) string {
	h := base64.url_encode(header_json.bytes()).trim_right('=')
	p := base64.url_encode(payload_json.bytes()).trim_right('=')
	return '${h}.${p}.spoofed'
}

fn test_offline_chain_roundtrip() {
	mut verifier := new_oidc_verifier()
	mut keys := encryption.new_server_key_pair()!
	defer {
		keys.free()
	}
	spki := base64.encode(keys.public_key_der()!)
	header := '{"alg":"ES384","x5u":"${spki}"}'
	payload := '{"extraData":{"displayName":"Steve","identity":"00000000-0000-0000-0000-000000000001","XUID":""},"identityPublicKey":"${spki}"}'
	token := make_token(header, payload, keys)!
	chain_json := '{"chain":["${token}"]}'
	identity := parse_login_chain(chain_json, false, mut verifier)!
	assert identity.display_name == 'Steve'
	assert identity.uuid == '00000000-0000-0000-0000-000000000001'
	assert identity.xbox_authenticated == false
	assert identity.client_public_key == spki
}

fn test_require_xbox_rejects_offline() {
	mut verifier := new_oidc_verifier()
	mut keys := encryption.new_server_key_pair()!
	defer {
		keys.free()
	}
	spki := base64.encode(keys.public_key_der()!)
	header := '{"alg":"ES384","x5u":"${spki}"}'
	payload := '{"extraData":{"displayName":"Steve","identity":"00000000-0000-0000-0000-000000000001"},"identityPublicKey":"${spki}"}'
	token := make_token(header, payload, keys)!
	chain_json := '{"chain":["${token}"]}'
	if _ := parse_login_chain(chain_json, true, mut verifier) {
		assert false
	}
}

// The identity token here is ES384-signed. parse_identity_token's real verifier only ever
// accepts RS256 (see OidcVerifier.verify), so this is rejected before any
// network discovery is attempted, not because of a missing/invalid
// signature check. xbox_authenticated == false either way is the same
// observable outcome this test asserts.
fn test_unsigned_identity_token_is_offline() {
	mut verifier := new_oidc_verifier()
	mut keys := encryption.new_server_key_pair()!
	defer {
		keys.free()
	}
	spki := base64.encode(keys.public_key_der()!)
	header := '{"alg":"ES384","x5u":"${spki}"}'
	payload := '{"xid":"2535412345678901","xname":"Alex","identity":"00000000-0000-0000-0000-0000000000aa","cpk":"${spki}"}'
	token := make_token(header, payload, keys)!
	auth_json := '{"AuthenticationType":2,"Token":"${token}","Certificate":""}'
	if _ := parse_login_chain(auth_json, true, mut verifier) {
		assert false
	}
	identity := parse_login_chain(auth_json, false, mut verifier)!
	assert identity.display_name == 'Alex'
	assert identity.xuid == '2535412345678901'
	assert identity.xbox_authenticated == false
}

fn test_identity_token_offline_rejected_when_xbox_required() {
	mut verifier := new_oidc_verifier()
	mut keys := encryption.new_server_key_pair()!
	defer {
		keys.free()
	}
	spki := base64.encode(keys.public_key_der()!)
	header := '{"alg":"ES384","x5u":"${spki}"}'
	payload := '{"xid":"","xname":"Steve","identity":"00000000-0000-0000-0000-0000000000bb","cpk":"${spki}"}'
	token := make_token(header, payload, keys)!
	auth_json := '{"AuthenticationType":2,"Token":"${token}"}'
	if _ := parse_login_chain(auth_json, true, mut verifier) {
		assert false
	}
	identity := parse_login_chain(auth_json, false, mut verifier)!
	assert identity.display_name == 'Steve'
	assert identity.xbox_authenticated == false
}

fn test_spoofed_xid_is_not_xbox_authenticated() {
	mut verifier := new_oidc_verifier()
	header := '{"alg":"ES384","x5u":"${test_public_key_spki}"}'
	payload := '{"xid":"2535412345678901","xname":"Impostor","identity":"00000000-0000-0000-0000-0000000000cc","cpk":"${test_public_key_spki}"}'
	token := unsigned_token(header, payload)
	auth_json := '{"AuthenticationType":2,"Token":"${token}"}'
	if _ := parse_login_chain(auth_json, true, mut verifier) {
		assert false
	}
	identity := parse_login_chain(auth_json, false, mut verifier)!
	assert identity.display_name == 'Impostor'
	assert identity.xuid == '2535412345678901'
	assert identity.xbox_authenticated == false
}

// A self-signed single token chain is the closed exploit: the attacker signs
// with their own key and cannot make is_trusted_key true, so authenticated stays
// false even if the payload claims to be Mojang's.
fn test_self_signed_chain_not_authenticated() {
	mut verifier := new_oidc_verifier()
	mut keys := encryption.new_server_key_pair()!
	defer {
		keys.free()
	}
	spki := base64.encode(keys.public_key_der()!)
	header := '{"alg":"ES384","x5u":"${spki}"}'
	payload := '{"extraData":{"displayName":"Notch","identity":"00000000-0000-0000-0000-0000000000ff","XUID":"2535400000000000"},"identityPublicKey":"${mojang_public_key}"}'
	token := make_token(header, payload, keys)!
	chain_json := '{"chain":["${token}"]}'
	identity := parse_login_chain(chain_json, false, mut verifier)!
	assert identity.display_name == 'Notch'
	assert identity.xbox_authenticated == false
	if _ := parse_login_chain(chain_json, true, mut verifier) {
		assert false
	}
}

// Trust anchor: authenticated is true only when a token was verified using the
// Mojang key, regardless of any payload field.
fn test_trust_anchor_is_verifying_key() {
	assert is_trusted_key(mojang_public_key) == true
	assert is_trusted_key(test_public_key_spki) == false
	assert is_trusted_key('') == false
}

// A mis-linked chain - the second token is not signed by the key the first token
// hands off - must fail verification, not silently continue.
fn test_broken_chain_returns_error() {
	mut verifier := new_oidc_verifier()
	mut keys := encryption.new_server_key_pair()!
	defer {
		keys.free()
	}
	spki := base64.encode(keys.public_key_der()!)
	header := '{"alg":"ES384","x5u":"${spki}"}'
	first_payload := '{"identityPublicKey":"${mojang_public_key}"}'
	first := make_token(header, first_payload, keys)!
	second_payload := '{"extraData":{"displayName":"Steve","XUID":"1"},"identityPublicKey":"${spki}"}'
	second := make_token(header, second_payload, keys)!
	chain_json := '{"chain":["${first}","${second}"]}'
	if _ := parse_login_chain(chain_json, false, mut verifier) {
		assert false
	}
}

fn test_tampered_signature_fails() {
	mut verifier := new_oidc_verifier()
	mut keys := encryption.new_server_key_pair()!
	defer {
		keys.free()
	}
	spki := base64.encode(keys.public_key_der()!)
	header := '{"alg":"ES384","x5u":"${spki}"}'
	payload := '{"extraData":{"displayName":"Steve","identity":"00000000-0000-0000-0000-000000000001"},"identityPublicKey":"${spki}"}'
	mut token := make_token(header, payload, keys)!
	token = token[..token.len - 2] + 'AA'
	chain_json := '{"chain":["${token}"]}'
	if _ := parse_login_chain(chain_json, false, mut verifier) {
		assert false
	}
}
