module network

import raknet
import sync
import src as protocol
import src.serializer
import logger

pub const default_compression_threshold = 256

@[heap]
pub struct Session {
mut:
	conn                &raknet.Conn = unsafe { nil }
	pool                protocol.PacketPool
	compression_enabled bool
	threshold           int = default_compression_threshold
	send_queue          [][]u8
	write_mutex         &sync.Mutex = sync.new_mutex()
pub mut:
	log &logger.Logger = unsafe { nil }
}

pub fn new_session(mut conn raknet.Conn, log &logger.Logger) &Session {
	return &Session{
		conn:        conn
		pool:        protocol.new_packet_pool()
		write_mutex: sync.new_mutex()
		log:         log
	}
}

pub fn (mut s Session) enable_compression(threshold int) {
	s.compression_enabled = true
	s.threshold = threshold
}

pub fn (mut s Session) read() ![]protocol.Packet {
	raw := s.conn.read_packet()!
	batch := decode_batch(raw, s.compression_enabled)!
	mut packets := []protocol.Packet{}
	for b in batch {
		mut r := serializer.new_reader(b)
		p := s.pool.decode(mut r) or {
			s.log.warn('Failed to decode packet: ${err}')
			continue
		}
		packets << p
	}
	return packets
}

fn (mut s Session) queue_locked(p protocol.Packet) {
	s.send_queue << protocol.encode_packet_to_bytes(p)
}

fn (mut s Session) flush_locked() ! {
	if s.send_queue.len == 0 {
		return
	}
	out := encode_batch(s.send_queue, s.compression_enabled, s.threshold)!
	s.conn.write(out)!
	s.send_queue.clear()
}

pub fn (mut s Session) queue(p protocol.Packet) {
	s.write_mutex.lock()
	s.queue_locked(p)
	s.write_mutex.unlock()
}

pub fn (mut s Session) flush() ! {
	s.write_mutex.lock()
	defer {
		s.write_mutex.unlock()
	}
	s.flush_locked()!
}

pub fn (mut s Session) send(p protocol.Packet) ! {
	s.write_mutex.lock()
	defer {
		s.write_mutex.unlock()
	}
	s.queue_locked(p)
	s.flush_locked()!
}

pub fn (mut s Session) remote_addr() string {
	return s.conn.remote_addr()
}

pub fn (mut s Session) close() {
	s.conn.close() or {}
}
