module network

import compress.deflate
import protocol.serializer

pub const game_packet_header = u8(0xfe)
pub const compression_flate = u8(0x00)
pub const compression_none = u8(0xff)

// Inbound frame bounds - a malformed or hostile peer must never drive
// unbounded work. All values are hard limits; a violation aborts decode and
// the caller disconnects the peer. Sized generously above vanilla traffic so
// legitimate clients are unaffected.
pub const max_compressed_batch = 2 * 1024 * 1024 // wire bytes accepted per read
pub const max_decompressed_batch = 8 * 1024 * 1024 // guards against decompression bombs
pub const max_packets_per_batch = 512
pub const max_single_packet = 2 * 1024 * 1024

pub fn encode_batch(packets [][]u8, compression_enabled bool, threshold int) ![]u8 {
	mut bw := serializer.new_writer()
	for pkt in packets {
		bw.write_varuint32(u32(pkt.len))
		bw.write_raw(pkt)
	}
	batch := bw.bytes()
	mut out := []u8{}
	out << game_packet_header
	if !compression_enabled {
		out << batch
		return out
	}
	if batch.len < threshold {
		out << compression_none
		out << batch
		return out
	}
	out << compression_flate
	// raw deflate: no zlib header flag, matches bedrock flate batch framing
	out << deflate.compress_raw(batch)!
	return out
}

pub fn decode_batch(payload []u8, compression_enabled bool) ![][]u8 {
	if payload.len == 0 {
		return error('empty batch payload')
	}
	if payload.len > max_compressed_batch {
		return error('batch payload too large: ${payload.len} bytes')
	}
	if payload[0] != game_packet_header {
		return error('invalid game packet header 0x${payload[0].hex()}')
	}
	body := unsafe { payload[1..] }
	mut batch := []u8{}
	if !compression_enabled {
		batch = body.clone()
	} else {
		if body.len == 0 {
			return error('missing compression algorithm byte')
		}
		algorithm := body[0]
		rest := body[1..]
		batch = match algorithm {
			compression_none { rest.clone() }
			compression_flate { deflate.decompress(rest)! }
			else { return error('unknown compression algorithm 0x${algorithm.hex()}') }
		}
	}
	// Guard against decompression bombs - a small flate frame can inflate to
	// gigabytes. We cannot cap the decompressor itself, so we reject after the
	// fact before doing any parsing work.
	if batch.len > max_decompressed_batch {
		return error('decompressed batch too large: ${batch.len} bytes')
	}
	mut r := serializer.new_reader(batch)
	mut packets := [][]u8{}
	for r.remaining() > 0 {
		length := int(r.read_varuint32()!)
		if length == 0 {
			return error('empty packet in batch')
		}
		if length > max_single_packet {
			return error('packet in batch too large: ${length} bytes')
		}
		packets << r.read_raw(length)!
		if packets.len > max_packets_per_batch {
			return error('too many packets in batch (> ${max_packets_per_batch})')
		}
	}
	return packets
}
