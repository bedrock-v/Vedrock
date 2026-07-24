module session

import protocol
import server.internal.encryption

// FakeTransport is an in memory network.Transport for tests: send/send_batch
// record packets instead of writing to a socket, so a test can construct a
// bare NetworkSession and assert on what it actually sent, with no real
// connection. It's also NetworkSession's zero-value transport default.
//
// Delivery now happens on a session's own outbound writer thread rather than
// synchronously inside deliver(), so a test observing `sent` from another
// thread has to wait for that thread to actually run. sent_notify carries one
// wakeup per completed send/send_batch so a waiter can block on the real
// event instead of polling `sent.len` on a timer.
@[heap]
pub struct FakeTransport {
pub mut:
	sent        []protocol.Packet
	sent_notify chan bool = chan bool{cap: 256}
}

pub fn (mut t FakeTransport) send(p protocol.Packet) ! {
	t.sent << p
	select {
		t.sent_notify <- true {}
		else {}
	}
}

pub fn (mut t FakeTransport) send_batch(packets []protocol.Packet) ! {
	t.sent << packets
	select {
		t.sent_notify <- true {}
		else {}
	}
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
