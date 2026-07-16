module network

import time
import raknet
import sync
import protocol
import protocol.serializer
import server.internal.logger
import server.internal.encryption

pub const default_compression_threshold = 256

pub fn is_connection_closed(err IError) bool {
	return err.code() == raknet.err_code_connection_closed
}

// Inbound rate limits, enforced per connection over a 1s sliding window. A peer
// that exceeds either bound is disconnected. Bedrock clients burst on chunk
// requests and movement but stay well under these ceilings.
pub const max_packets_per_second = 1000
pub const max_bytes_per_second = 8 * 1024 * 1024

// A connection that has not finished logging in may only send a handful of
// packets (network settings, login, resource-pack handshake). This caps the
// work an unauthenticated peer can force before we know who it is.
pub const max_prelogin_packets = 64

@[heap]
pub struct Session {
mut:
	conn                &raknet.Conn = unsafe { nil }
	pool                protocol.PacketPool
	compression_enabled bool
	threshold           int                 = default_compression_threshold
	cipher              &encryption.Context = unsafe { nil }
	send_queue          [][]u8
	write_mutex         &sync.Mutex = sync.new_mutex()
	logged_in           bool
	prelogin_packets    int
	window_start        time.Time = time.now()
	window_packets      int
	window_bytes        int
pub mut:
	log &logger.Logger = unsafe { nil }
}

pub fn new_session(mut conn raknet.Conn, log &logger.Logger) &Session {
	return &Session{
		conn:         conn
		pool:         protocol.new_packet_pool()
		write_mutex:  sync.new_mutex()
		window_start: time.now()
		log:          log
	}
}

// mark_logged_in lifts the pre-login packet cap once authentication completes.
pub fn (mut s Session) mark_logged_in() {
	s.logged_in = true
}

// check_rate enforces the per-connection inbound rate limit over a sliding 1s
// window. Returns an error - which the read loop treats as a disconnect - when
// a peer exceeds the packet or byte ceiling. Fails closed, never panics.
fn (mut s Session) check_rate(raw_len int, packet_count int) ! {
	now := time.now()
	if now - s.window_start >= time.second {
		s.window_start = now
		s.window_packets = 0
		s.window_bytes = 0
	}
	s.window_packets += packet_count
	s.window_bytes += raw_len
	if s.window_packets > max_packets_per_second {
		return error('inbound packet rate exceeded (${s.window_packets}/s)')
	}
	if s.window_bytes > max_bytes_per_second {
		return error('inbound byte rate exceeded (${s.window_bytes}/s)')
	}
}

pub fn (mut s Session) enable_compression(threshold int) {
	s.compression_enabled = true
	s.threshold = threshold
}

// enable_encryption installs the per-session cipher once the handshake has
// completed. From this point every batch body (after the 0xfe header) is
// encrypted outbound and decrypted inbound. Guarded by write_mutex so it never
// races an in-flight flush.
pub fn (mut s Session) enable_encryption(mut ctx encryption.Context) {
	s.write_mutex.lock()
	s.cipher = ctx
	s.write_mutex.unlock()
}

pub fn (s &Session) encryption_enabled() bool {
	return s.cipher != unsafe { nil }
}

pub fn (mut s Session) read() ![]protocol.Packet {
	mut raw := s.conn.read_packet()!
	raw = s.decrypt_frame(raw)!
	batch := decode_batch(raw, s.compression_enabled)!
	s.check_rate(raw.len, batch.len)!
	if !s.logged_in {
		s.prelogin_packets += batch.len
		if s.prelogin_packets > max_prelogin_packets {
			return error('too many packets before login (${s.prelogin_packets})')
		}
	}
	mut packets := []protocol.Packet{}
	for b in batch {
		mut head_reader := serializer.new_reader(b)
		header := protocol.read_packet_header(mut head_reader) or { continue }
		if header.pid == protocol.player_auth_input_packet {
			packets << decode_auth_input_prefix(mut head_reader) or { continue }
			continue
		}
		mut r := serializer.new_reader(b)
		p := s.pool.decode(mut r) or {
			s.log.warn('Failed to decode packet pid=0x${header.pid:02x}: ${err}')
			continue
		}
		packets << p
	}
	return packets
}

fn decode_auth_input_prefix(mut r serializer.Reader) !protocol.Packet {
	pitch := r.le_f32()!
	yaw := r.le_f32()!
	position := r.read_vector3()!
	return &protocol.PlayerAuthInputPacket{
		pitch:    pitch
		yaw:      yaw
		position: position
	}
}

// decrypt_frame decrypts the batch body of an inbound wire frame when the
// cipher is active. The 0xfe game-packet header stays in cleartext - only the
// bytes after it are encrypted, matching the Bedrock framing. Called only from
// the single read thread, so the decrypt keystream needs no extra lock.
fn (mut s Session) decrypt_frame(raw []u8) ![]u8 {
	if s.cipher == unsafe { nil } {
		return raw
	}
	if raw.len == 0 || raw[0] != game_packet_header {
		return error('invalid game packet header on encrypted frame')
	}
	body := unsafe { raw[1..] }
	plain := s.cipher.decrypt(body)!
	mut out := []u8{cap: plain.len + 1}
	out << game_packet_header
	out << plain
	return out
}

// encrypt_frame encrypts the batch body of an outbound frame when the cipher is
// active, leaving the 0xfe header in cleartext. Callers must hold write_mutex.
fn (mut s Session) encrypt_frame(frame []u8) []u8 {
	if s.cipher == unsafe { nil } {
		return frame
	}
	body := frame[1..]
	cipher := s.cipher.encrypt(body)
	mut out := []u8{cap: cipher.len + 1}
	out << game_packet_header
	out << cipher
	return out
}

fn (mut s Session) queue_locked(p protocol.Packet) {
	s.send_queue << protocol.encode_packet_to_bytes(p)
}

fn (mut s Session) flush_locked() ! {
	if s.send_queue.len == 0 {
		return
	}
	out := encode_batch(s.send_queue, s.compression_enabled, s.threshold)!
	s.conn.write(s.encrypt_frame(out))!
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

pub fn (mut s Session) send_batch(packets []protocol.Packet) ! {
	s.write_mutex.lock()
	defer {
		s.write_mutex.unlock()
	}
	for p in packets {
		s.queue_locked(p)
	}
	s.flush_locked()!
}

pub fn (mut s Session) remote_addr() string {
	return s.conn.remote_addr()
}

pub fn (mut s Session) close() {
	s.conn.close() or {}
}
