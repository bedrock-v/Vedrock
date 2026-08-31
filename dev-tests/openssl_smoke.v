import crypto.ecdsa
import server.internal.encryption

fn main() {
	private_key, public_key := ecdsa.generate_key() or {
		eprintln('ecdsa generate_key failed: ${err}')
		return
	}
	_ = private_key
	_ = public_key

	mut server_key := encryption.new_server_key_pair() or {
		eprintln('vedrock key generation failed: ${err}')
		return
	}
	defer {
		server_key.free()
	}

	println('both key paths worked')
}
