module auth

import crypto.ecdsa
import encoding.base64

const test_private_key_pem = '-----BEGIN PRIVATE KEY-----
MIG2AgEAMBAGByqGSM49AgEGBSuBBAAiBIGeMIGbAgEBBDA60Sz/6mR15FtbH8zh
CcPquhLVbL5RQ3tFb8OBWq1XhK4LiJi0ElIjD1Xu/ghGWD6hZANiAAQxE3lBAsiY
+8qTmo78MtLgwwNcgpbEE/FRSfgwUwaeO+xXySeaR6tY4OFoeGrnlFg82z0dY/zA
t0saDAHsX5rVGAhRm7N3C956r/1x/04YodfQB1z1i4TTn6aiSqjiqoM=
-----END PRIVATE KEY-----'

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

fn der_to_raw(der []u8) []u8 {
	mut i := 1
	if der[i] & 0x80 != 0 {
		i += 1 + int(der[i] & 0x7f)
	} else {
		i++
	}
	i++
	r_len := int(der[i])
	i++
	r := der[i..i + r_len]
	i += r_len
	i++
	s_len := int(der[i])
	i++
	s := der[i..i + s_len]
	mut out := left_pad(r, 48)
	out << left_pad(s, 48)
	return out
}

fn left_pad(value []u8, size int) []u8 {
	mut v := value.clone()
	for v.len > size && v[0] == 0 {
		v = v[1..]
	}
	mut out := []u8{len: size - v.len, init: u8(0)}
	out << v
	return out
}

fn make_token(header_json string, payload_json string, priv ecdsa.PrivateKey) !string {
	h := base64.url_encode(header_json.bytes()).trim_right('=')
	p := base64.url_encode(payload_json.bytes()).trim_right('=')
	signing_input := '${h}.${p}'
	der := priv.sign(signing_input.bytes(), ecdsa.SignerOpts{})!
	raw := der_to_raw(der)
	sig := base64.url_encode(raw).trim_right('=')
	return '${signing_input}.${sig}'
}

fn test_offline_chain_roundtrip() {
	priv := ecdsa.privkey_from_string(test_private_key_pem)!
	header := '{"alg":"ES384","x5u":"${test_public_key_spki}"}'
	payload := '{"extraData":{"displayName":"Steve","identity":"00000000-0000-0000-0000-000000000001","XUID":""},"identityPublicKey":"${test_public_key_spki}"}'
	token := make_token(header, payload, priv)!
	chain_json := '{"chain":["${token}"]}'
	identity := parse_login_chain(chain_json, false)!
	assert identity.display_name == 'Steve'
	assert identity.uuid == '00000000-0000-0000-0000-000000000001'
	assert identity.xbox_authenticated == false
	assert identity.client_public_key == test_public_key_spki
}

fn test_require_xbox_rejects_offline() {
	priv := ecdsa.privkey_from_string(test_private_key_pem)!
	header := '{"alg":"ES384","x5u":"${test_public_key_spki}"}'
	payload := '{"extraData":{"displayName":"Steve","identity":"00000000-0000-0000-0000-000000000001"},"identityPublicKey":"${test_public_key_spki}"}'
	token := make_token(header, payload, priv)!
	chain_json := '{"chain":["${token}"]}'
	if _ := parse_login_chain(chain_json, true) {
		assert false
	}
}

fn test_identity_token_path() {
	priv := ecdsa.privkey_from_string(test_private_key_pem)!
	header := '{"alg":"ES384","x5u":"${test_public_key_spki}"}'
	payload := '{"xid":"2535412345678901","xname":"Alex","identity":"00000000-0000-0000-0000-0000000000aa","cpk":"${test_public_key_spki}"}'
	token := make_token(header, payload, priv)!
	auth_json := '{"AuthenticationType":2,"Token":"${token}","Certificate":""}'
	identity := parse_login_chain(auth_json, true)!
	assert identity.display_name == 'Alex'
	assert identity.xuid == '2535412345678901'
	assert identity.xbox_authenticated == true
}

fn test_identity_token_offline_rejected_when_xbox_required() {
	priv := ecdsa.privkey_from_string(test_private_key_pem)!
	header := '{"alg":"ES384","x5u":"${test_public_key_spki}"}'
	payload := '{"xid":"","xname":"Steve","identity":"00000000-0000-0000-0000-0000000000bb","cpk":"${test_public_key_spki}"}'
	token := make_token(header, payload, priv)!
	auth_json := '{"AuthenticationType":2,"Token":"${token}"}'
	if _ := parse_login_chain(auth_json, true) {
		assert false
	}
	identity := parse_login_chain(auth_json, false)!
	assert identity.display_name == 'Steve'
	assert identity.xbox_authenticated == false
}

// A self-signed single-token chain is the closed exploit: the attacker signs
// with their own key and cannot make is_trusted_key true, so authenticated stays
// false even if the payload claims to be Mojang's.
fn test_self_signed_chain_not_authenticated() {
	priv := ecdsa.privkey_from_string(test_private_key_pem)!
	header := '{"alg":"ES384","x5u":"${test_public_key_spki}"}'
	payload := '{"extraData":{"displayName":"Notch","identity":"00000000-0000-0000-0000-0000000000ff","XUID":"2535400000000000"},"identityPublicKey":"${mojang_public_key}"}'
	token := make_token(header, payload, priv)!
	chain_json := '{"chain":["${token}"]}'
	identity := parse_login_chain(chain_json, false)!
	assert identity.display_name == 'Notch'
	assert identity.xbox_authenticated == false
	if _ := parse_login_chain(chain_json, true) {
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
	priv := ecdsa.privkey_from_string(test_private_key_pem)!
	header := '{"alg":"ES384","x5u":"${test_public_key_spki}"}'
	first_payload := '{"identityPublicKey":"${mojang_public_key}"}'
	first := make_token(header, first_payload, priv)!
	second_payload := '{"extraData":{"displayName":"Steve","XUID":"1"},"identityPublicKey":"${test_public_key_spki}"}'
	second := make_token(header, second_payload, priv)!
	chain_json := '{"chain":["${first}","${second}"]}'
	if _ := parse_login_chain(chain_json, false) {
		assert false
	}
}

fn test_tampered_signature_fails() {
	priv := ecdsa.privkey_from_string(test_private_key_pem)!
	header := '{"alg":"ES384","x5u":"${test_public_key_spki}"}'
	payload := '{"extraData":{"displayName":"Steve","identity":"00000000-0000-0000-0000-000000000001"},"identityPublicKey":"${test_public_key_spki}"}'
	mut token := make_token(header, payload, priv)!
	token = token[..token.len - 2] + 'AA'
	chain_json := '{"chain":["${token}"]}'
	if _ := parse_login_chain(chain_json, false) {
		assert false
	}
}
