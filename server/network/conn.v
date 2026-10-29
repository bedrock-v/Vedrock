module network

import crypto.ecdsa
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
	// public_key is the key the peer proved it holds while the connection was
	// opened if the transport made it prove one.
	public_key() ?ecdsa.PublicKey
	// buffered_amount is how many bytes written have not gone out yet. Writes
	// don't wait for the peer, this is where a peer that stops reading shows.
	buffered_amount() u64
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
	message := c.wire.read_message()!
	c.reads++
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
	c.wire.write_message(encode_batch(encoded, c.compression, c.threshold)!)!
}

// enable_compression compresses every message from here on. The client is told
// the threshold in NetworkSettings and applies it to its own messages. Both
// ends change over at the same packet.
pub fn (mut c Conn) enable_compression(threshold int) {
	c.compression = true
	c.threshold = threshold
}

pub fn (mut c Conn) remote() string {
	return c.wire.remote()
}

// public_key is the key the peer proved it holds if it proved one.
pub fn (mut c Conn) public_key() ?ecdsa.PublicKey {
	return c.wire.public_key()
}

// buffered_amount is how many bytes written to the client have not gone out
// yet.
pub fn (mut c Conn) buffered_amount() u64 {
	return c.wire.buffered_amount()
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
