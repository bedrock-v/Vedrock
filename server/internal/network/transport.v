module network

import bedrock_v.protocol
import server.internal.encryption

// Transport is everything NetworkSession needs from the wire: framed
// packet send/receive plus the handshake time hooks (compression,
// encryption, marking login complete).
pub interface Transport {
	// disable_encryption reports whether the transport already encrypts, in
	// which case the protocol layer must not negotiate its own encryption.
	disable_encryption() bool
	// transport_identity is the key the peer proved it holds while the transport
	// was being set up, base64 SubjectPublicKeyInfo, or empty when it proved
	// none. A login chain signed with a different key did not come from whoever
	// opened this connection.
	transport_identity() string
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
