module net

import sync
import bedrock_v.protocol
import bedrock_v.protocol.serializer

// Wire is the transport under a connection. It carries whole messages in and
// out and knows nothing about what they hold.
pub interface Wire {
mut:
	read_message() ![]u8
	write_message(b []u8) !
	// remote names the peer for logs and messages.
	remote() string
	// encrypted reports whether the transport already encrypts every byte. The
	// game's own encryption handshake is skipped when it does.
	encrypted() bool
	close()
}

// Conn is one client's connection. It holds the wire, frames batches over it
// and hands out the packets that come back.
//
// A read hands back one packet. One message carries a batch of them and the
// session handles each on its world before asking for the next. The rest of
// the batch waits here.
@[heap]
pub struct Conn {
mut:
	wire Wire
	pool protocol.PacketPool
	// pending holds the packets of the message being read and next the one to
	// hand over.
	pending []protocol.Packet
	next    int
	// dropped counts packets this server has no type for.
	dropped int
	// reads counts the messages taken off the wire.
	reads       int
	compression bool
	threshold   int = default_compression_threshold
	// cipher is the game's own encryption, installed when the transport does
	// not encrypt on its own. nil until the handshake sets it up.
	cipher &Cipher = unsafe { nil }
	// writes serializes outbound messages. The cipher's keystream is stateful,
	// so messages have to be encrypted in the order they are written.
	writes &sync.Mutex = sync.new_mutex()
}

// new_conn wraps a wire in the packet layer.
pub fn new_conn(mut w Wire) &Conn {
	return &Conn{
		wire: w
		pool: protocol.new_pool()
	}
}

// max_empty_reads is how many messages in a row may carry nothing this server
// can decode. A peer that sends only packets with no type here would otherwise
// keep a read going for as long as it likes.
const max_empty_reads = 16

// read returns the next packet the client sent, waiting for one if it has to.
pub fn (mut c Conn) read() !protocol.Packet {
	mut empty := 0
	for c.next >= c.pending.len {
		c.fill()!
		if c.pending.len > 0 {
			continue
		}
		empty++
		if empty > max_empty_reads {
			return error('${max_empty_reads} messages in a row carried no packet this server knows')
		}
	}
	p := c.pending[c.next]
	c.next++
	return p
}

// fill reads one message and decodes the packets in it.
//
// A packet this server has no type for is counted and skipped. A client sends
// plenty the server doesn't implement and one of them is not a reason to
// drop the connection.
fn (mut c Conn) fill() ! {
	mut message := c.wire.read_message()!
	c.reads++
	if c.cipher != unsafe { nil } {
		// Only the reading thread decrypts. The receive keystream needs no lock
		// of its own.
		message = c.cipher.decrypt(message)!
	}
	batch := decode_batch(message, c.compression)!
	c.pending = []protocol.Packet{cap: batch.len}
	c.next = 0
	for b in batch {
		mut r := serializer.new_reader(b)
		p := c.pool.decode(mut r) or {
			c.dropped++
			continue
		}
		c.pending << p
	}
}

// write sends one packet.
pub fn (mut c Conn) write(p protocol.Packet) ! {
	c.write_batch([p])!
}

// write_batch sends several packets in one message. That is one round of
// framing and compression instead of one per packet.
pub fn (mut c Conn) write_batch(ps []protocol.Packet) ! {
	mut encoded := [][]u8{cap: ps.len}
	for p in ps {
		encoded << protocol.encode_packet_to_bytes(p)
	}
	batch := encode_batch(encoded, c.compression, c.threshold)!
	c.writes.lock()
	defer {
		c.writes.unlock()
	}
	message := if c.cipher != unsafe { nil } { c.cipher.encrypt(batch) } else { batch }
	c.wire.write_message(message)!
}

// enable_compression compresses every message from here on. The client is told
// the threshold in NetworkSettings and applies it to its own messages. Both
// ends change over at the same packet.
pub fn (mut c Conn) enable_compression(threshold int) {
	c.compression = true
	c.threshold = threshold
}

// enable_encryption encrypts every message from here on.
//
// The packet that tells the client to expect this has to have gone out first.
// The client reads that one in the clear and installs its own cipher after it.
fn (mut c Conn) enable_encryption(mut cipher Cipher) {
	c.writes.lock()
	c.cipher = cipher
	c.writes.unlock()
}

// encrypting reports whether the game's own encryption is on. The transport may
// be encrypting on its own. See Wire.encrypted.
pub fn (mut c Conn) encrypting() bool {
	return c.cipher != unsafe { nil }
}

pub fn (mut c Conn) remote() string {
	return c.wire.remote()
}

// encrypted reports whether the transport encrypts every byte on its own.
pub fn (mut c Conn) encrypted() bool {
	return c.wire.encrypted()
}

// dropped is how many packets this server had no type for.
pub fn (mut c Conn) dropped() int {
	return c.dropped
}

// reads is how many messages this connection has taken off the wire.
pub fn (mut c Conn) reads() int {
	return c.reads
}

pub fn (mut c Conn) close() {
	c.wire.close()
}
