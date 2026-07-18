module session

import protocol
import server.internal.encryption

// FakeTransport is an in memory network.Transport for tests: send/send_batch
// record packets instead of writing to a socket, so a test can construct a
// bare NetworkSession and assert on what it actually sent, with no real
// connection. It's also NetworkSession's zero-value transport default.
@[heap]
pub struct FakeTransport {
pub mut:
	sent []protocol.Packet
}

pub fn (mut t FakeTransport) send(p protocol.Packet) ! {
	t.sent << p
}

pub fn (mut t FakeTransport) send_batch(packets []protocol.Packet) ! {
	t.sent << packets
}

pub fn (mut t FakeTransport) read() ![]protocol.Packet {
	return []protocol.Packet{}
}

pub fn (t &FakeTransport) remote_addr() string {
	return 'fake:0'
}

pub fn (mut t FakeTransport) close() {}

pub fn (mut t FakeTransport) mark_logged_in() {}

pub fn (mut t FakeTransport) enable_compression(threshold int) {}

pub fn (mut t FakeTransport) enable_encryption(mut ctx encryption.Context) {}
