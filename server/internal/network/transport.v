module network

import protocol
import server.internal.encryption

// Transport is everything NetworkSession needs from the wire: framed
// packet send/receive plus the handshake time hooks (compression,
// encryption, marking login complete).
pub interface Transport {
	// disable_encryption reports whether the transport already encrypts, in
	// which case the protocol layer must not negotiate its own encryption.
	disable_encryption() bool
mut:
	send(p protocol.Packet) !
	send_batch(packets []protocol.Packet) !
	read() ![]protocol.Packet
	remote_addr() string
	close()
	mark_logged_in()
	enable_compression(threshold int)
	enable_encryption(mut ctx encryption.Context)
}
