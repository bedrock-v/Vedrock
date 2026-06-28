module auth

import crypto.ecdsa
import encoding.base64
import x.json2

pub struct Jwt {
pub:
	header  map[string]json2.Any
	payload map[string]json2.Any
}

pub fn decode_jwt(token string) !Jwt {
	parts := token.split('.')
	if parts.len != 3 {
		return error('invalid JWT format')
	}
	header := json2.decode[json2.Any](b64url_decode(parts[0])!.bytestr())!.as_map()
	payload := json2.decode[json2.Any](b64url_decode(parts[1])!.bytestr())!.as_map()
	return Jwt{
		header:  header
		payload: payload
	}
}

pub fn verify_jwt(token string, public_key_b64 string) !bool {
	parts := token.split('.')
	if parts.len != 3 {
		return error('invalid JWT format')
	}
	signing_input := '${parts[0]}.${parts[1]}'
	raw_signature := b64url_decode(parts[2])!
	der_signature := ecdsa_signature_to_der(raw_signature)!
	public_key := ecdsa.pubkey_from_string(pem_from_spki(public_key_b64))!
	return public_key.verify(signing_input.bytes(), der_signature, ecdsa.SignerOpts{})!
}

fn b64url_decode(data string) ![]u8 {
	mut padded := data
	remainder := padded.len % 4
	if remainder == 2 {
		padded += '=='
	} else if remainder == 3 {
		padded += '='
	}
	return base64.url_decode(padded)
}

fn pem_from_spki(public_key_b64 string) string {
	mut body := ''
	mut i := 0
	for i < public_key_b64.len {
		end := if i + 64 < public_key_b64.len { i + 64 } else { public_key_b64.len }
		body += public_key_b64[i..end] + '\n'
		i += 64
	}
	return '-----BEGIN PUBLIC KEY-----\n${body}-----END PUBLIC KEY-----\n'
}

fn ecdsa_signature_to_der(raw []u8) ![]u8 {
	if raw.len == 0 || raw.len % 2 != 0 {
		return error('invalid raw signature length ${raw.len}')
	}
	half := raw.len / 2
	r := der_integer(raw[..half])
	s := der_integer(raw[half..])
	mut body := []u8{}
	body << r
	body << s
	mut out := []u8{}
	out << 0x30
	out << u8(body.len)
	out << body
	return out
}

fn der_integer(value []u8) []u8 {
	mut start := 0
	for start < value.len - 1 && value[start] == 0 {
		start++
	}
	trimmed := value[start..]
	mut out := []u8{}
	out << 0x02
	if trimmed[0] & 0x80 != 0 {
		out << u8(trimmed.len + 1)
		out << 0x00
		out << trimmed
	} else {
		out << u8(trimmed.len)
		out << trimmed
	}
	return out
}
