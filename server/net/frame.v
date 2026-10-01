module net

import compress.deflate
import bedrock_v.protocol.serializer

// The first byte of a message says how the batch after it is compressed. A
// NetherNet message is that byte and the batch, with no packet header in front.
const compression_flate = u8(0x00)
const compression_none = u8(0xff)

// Bounds on an inbound message. A peer that breaks one of them is disconnected.
// A peer decides what it sends and without these limits it would also decide
// how much work one read costs.
const max_compressed_batch = 2 * 1024 * 1024
const max_decompressed_batch = 8 * 1024 * 1024
const max_packets_per_batch = 512
const max_single_packet = 2 * 1024 * 1024

// encode_batch frames already encoded packets into one message.
fn encode_batch(packets [][]u8, compression bool, threshold int) ![]u8 {
	mut bw := serializer.new_writer()
	for p in packets {
		bw.write_varuint32(u32(p.len))
		bw.write_raw(p)
	}
	batch := bw.bytes()
	if !compression {
		return batch
	}
	mut out := []u8{cap: batch.len + 1}
	if batch.len < threshold {
		out << compression_none
		out << batch
		return out
	}
	out << compression_flate
	// Raw deflate with no zlib header, which is what the game calls flate here.
	out << deflate.compress_raw(batch)!
	return out
}

// decode_batch splits a message into the encoded packets it carries.
fn decode_batch(payload []u8, compression bool) ![][]u8 {
	if payload.len == 0 {
		return error('empty batch')
	}
	if payload.len > max_compressed_batch {
		return error('batch of ${payload.len} bytes is over the ${max_compressed_batch} byte limit')
	}
	mut batch := []u8{}
	if !compression {
		batch = payload.clone()
	} else {
		algorithm := payload[0]
		body := payload[1..]
		batch = match algorithm {
			compression_none { body.clone() }
			compression_flate { deflate.decompress(body)! }
			else { return error('unknown compression algorithm 0x${algorithm.hex()}') }
		}
	}
	if batch.len > max_decompressed_batch {
		return error('batch of ${batch.len} bytes decompressed is over the ${max_decompressed_batch} byte limit')
	}
	mut r := serializer.new_reader(batch)
	mut packets := [][]u8{}
	for r.remaining() > 0 {
		length := int(r.read_varuint32()!)
		if length == 0 {
			return error('empty packet in batch')
		}
		if length > max_single_packet {
			return error('packet of ${length} bytes is over the ${max_single_packet} byte limit')
		}
		packets << r.read_raw(length)!
		if packets.len > max_packets_per_batch {
			return error('batch holds more than ${max_packets_per_batch} packets')
		}
	}
	return packets
}
