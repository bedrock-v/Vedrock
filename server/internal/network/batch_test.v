module network

import bedrock_v.protocol.serializer

fn test_batch_roundtrip_uncompressed() {
	packets := [
		[u8(0x01), 0x02, 0x03],
		[u8(0xaa), 0xbb],
	]
	encoded := encode_batch(packets, false, 0)!
	decoded := decode_batch(encoded, false)!
	assert decoded.len == 2
	assert decoded[0] == packets[0]
	assert decoded[1] == packets[1]
}

fn test_batch_roundtrip_nop_below_threshold() {
	packets := [[u8(0x10), 0x20, 0x30]]
	encoded := encode_batch(packets, true, 1024)!
	assert encoded[0] == compression_none
	decoded := decode_batch(encoded, true)!
	assert decoded.len == 1
	assert decoded[0] == packets[0]
}

fn test_batch_roundtrip_flate_above_threshold() {
	mut big := []u8{len: 2048, init: u8(0x41)}
	packets := [big]
	encoded := encode_batch(packets, true, 256)!
	assert encoded[0] == compression_flate
	assert encoded.len < 1 + big.len
	decoded := decode_batch(encoded, true)!
	assert decoded.len == 1
	assert decoded[0] == big
}

fn test_decode_rejects_unknown_compression_algorithm() {
	bad := [u8(0x7f), 0x01]
	if _ := decode_batch(bad, true) {
		assert false
	}
}

fn test_decode_rejects_oversized_compressed_payload() {
	mut huge := []u8{len: max_compressed_batch + 1, init: u8(0x00)}
	if _ := decode_batch(huge, false) {
		assert false
	}
}

fn test_decode_rejects_oversized_single_packet() {
	mut bw := serializer.new_writer()
	bw.write_varuint32(u32(max_single_packet + 1))
	if _ := decode_batch(bw.bytes(), false) {
		assert false
	}
}

fn test_decode_rejects_too_many_packets() {
	mut bw := serializer.new_writer()
	for _ in 0 .. max_packets_per_batch + 1 {
		bw.write_varuint32(1)
		bw.write_raw([u8(0x00)])
	}
	if _ := decode_batch(bw.bytes(), false) {
		assert false
	}
}
