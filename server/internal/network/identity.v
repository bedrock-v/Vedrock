module network

import crypto.ecdsa
import encoding.hex
import bedrock_v.nethernet
import os

// identity_curve is fixed by NetherNet: the assertion is signed with ES384, so
// the key has to be on P-384.
const identity_curve = ecdsa.Nid.secp384r1

// identity_key_size is the P-384 private key size. A key read back from the
// legacy format is padded to it, because one whose leading bytes are zero would
// otherwise come back short and name a different key.
const identity_key_size = 48

// load_identity returns the identity the server answers under, creating the key
// at path the first time.
//
// The key is kept across restarts so a client that remembers the server keeps
// seeing the same one. The token itself is short lived and reissued per
// connection by nethernet.
pub fn load_identity(path string, domain string) !nethernet.Identity {
	return nethernet.generate_server_identity(load_identity_key(path)!, domain)!
}

fn load_identity_key(path string) !ecdsa.PrivateKey {
	if os.exists(path) {
		return read_identity_key(path)!
	}
	// An earlier version wrote a bare hex seed next to the config. Reading it
	// keeps a server recognisable to the clients that already trust it; it is
	// rewritten as PEM so the next start finds it where it now belongs.
	if legacy := legacy_identity_key(path) {
		write_identity_key(path, legacy)!
		return legacy
	}
	private_key := ecdsa.PrivateKey.new(nid: identity_curve)!
	write_identity_key(path, private_key)!
	return private_key
}

fn read_identity_key(path string) !ecdsa.PrivateKey {
	text := os.read_file(path)!
	if text.contains('-----BEGIN ') {
		return nethernet.parse_private_key_pem(text) or {
			error('malformed identity key in ${path}: ${err.msg()}')
		}
	}
	return decode_legacy_key(text) or { error('malformed identity key in ${path}: ${err.msg()}') }
}

// legacy_identity_key_name is where the hex seed used to live, relative to the
// working directory rather than to the configured path.
const legacy_identity_key_name = 'identity.key'

fn legacy_identity_key(path string) ?ecdsa.PrivateKey {
	if os.file_name(path) == legacy_identity_key_name || !os.exists(legacy_identity_key_name) {
		return none
	}
	text := os.read_file(legacy_identity_key_name) or { return none }
	return decode_legacy_key(text) or { return none }
}

fn decode_legacy_key(text string) !ecdsa.PrivateKey {
	seed := hex.decode(text.trim_space())!
	return ecdsa.new_key_from_seed(seed, nid: identity_curve, fixed_size: true)
}

fn write_identity_key(path string, private_key ecdsa.PrivateKey) ! {
	seed := private_key.bytes()!
	if seed.len > identity_key_size {
		return error('identity key of ${seed.len} bytes is not on P-384')
	}
	pem := nethernet.encode_private_key_pem(private_key)!

	dir := os.dir(path)
	if dir != '' && !os.exists(dir) {
		os.mkdir_all(dir)!
	}
	os.write_file(path, pem)!
	// The key identifies the server, so keep it out of reach of other users on
	// the host.
	os.chmod(path, 0o600)!
}
