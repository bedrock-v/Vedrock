module network

import crypto.ecdsa
import encoding.hex
import nethernet
import os

// identity_curve is fixed by NetherNet: the assertion is signed with ES384, so
// the key has to be on P-384.
const identity_curve = ecdsa.Nid.secp384r1

// identity_key_size is the P-384 private key size. The stored key is padded to
// it, because a key whose leading bytes are zero would otherwise come back
// short and be rejected on the next start.
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
		encoded := os.read_file(path)!.trim_space()
		seed := hex.decode(encoded) or { return error('malformed identity key in ${path}') }
		return ecdsa.new_key_from_seed(seed, nid: identity_curve, fixed_size: true)
	}
	private_key := ecdsa.PrivateKey.new(nid: identity_curve)!
	write_identity_key(path, private_key.bytes()!)!
	return private_key
}

fn write_identity_key(path string, seed []u8) ! {
	if seed.len > identity_key_size {
		return error('identity key of ${seed.len} bytes is not on P-384')
	}
	dir := os.dir(path)
	if dir != '' && !os.exists(dir) {
		os.mkdir_all(dir)!
	}
	mut padded := []u8{len: identity_key_size - seed.len}
	padded << seed
	os.write_file(path, hex.encode(padded))!
	// The key identifies the server, so keep it out of reach of other users on
	// the host.
	os.chmod(path, 0o600)!
}
