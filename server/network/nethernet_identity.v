module network

import os
import crypto.ecdsa
import bedrock_v.nethernet as nn

// A P-384 public key is 97 bytes uncompressed: a prefix byte and two 48-byte
// coordinates.
const identity_public_key_size = 97

fn load_identity(path string, domain string) !nn.Identity {
	return nn.generate_server_identity(load_identity_key(path)!, domain)!
}

// load_identity_key reads the server's key or generates one and keeps it at
// path when there is none yet.
fn load_identity_key(path string) !ecdsa.PrivateKey {
	if !os.exists(path) {
		key := ecdsa.PrivateKey.new(nid: .secp384r1)!
		write_identity_key(path, key)!
		return key
	}
	key := nn.parse_private_key_pem(os.read_file(path)!) or {
		return error('identity key in ${path} is not a PEM EC private key: ${err}')
	}
	if key.public_key()!.uncompressed_bytes()!.len != identity_public_key_size {
		return error('identity key in ${path} is not on P-384')
	}
	return key
}

fn write_identity_key(path string, key ecdsa.PrivateKey) ! {
	dir := os.dir(path)
	if dir != '' && !os.exists(dir) {
		os.mkdir_all(dir)!
	}
	mut f := os.open_file(path, 'w', 0o600)!
	defer {
		f.close()
	}
	f.write_string(nn.encode_private_key_pem(key)!)!
}
