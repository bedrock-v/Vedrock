module nethernet

import os
import crypto.ecdsa
import encoding.hex
import bedrock_v.nethernet as nn

const identity_curve = ecdsa.Nid.secp384r1

const identity_key_size = 48

fn load_identity(path string) !nn.Identity {
	return nn.generate_server_identity(load_identity_key(path)!, 'vedrock')!
}

fn load_identity_key(path string) !ecdsa.PrivateKey {
	if os.exists(path) {
		stored := os.read_file(path)!.trim_space()
		seed := hex.decode(stored) or { return error('identity key in ${path} is malformed') }
		return ecdsa.new_key_from_seed(seed, nid: identity_curve, fixed_size: true)
	}
	key := ecdsa.PrivateKey.new(nid: identity_curve)!
	write_identity_key(path, key.bytes()!)!
	return key
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
	os.chmod(path, 0o600)!
}
