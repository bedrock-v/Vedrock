module network

fn test_batch_roundtrip_uncompressed() {
	packets := [
		[u8(0x01), 0x02, 0x03],
		[u8(0xaa), 0xbb],
	]
	encoded := encode_batch(packets, false, 0)!
	assert encoded[0] == game_packet_header
	decoded := decode_batch(encoded, false)!
	assert decoded.len == 2
	assert decoded[0] == packets[0]
	assert decoded[1] == packets[1]
}

fn test_batch_roundtrip_nop_below_threshold() {
	packets := [[u8(0x10), 0x20, 0x30]]
	encoded := encode_batch(packets, true, 1024)!
	assert encoded[0] == game_packet_header
	assert encoded[1] == compression_none
	decoded := decode_batch(encoded, true)!
	assert decoded.len == 1
	assert decoded[0] == packets[0]
}

fn test_batch_roundtrip_zlib_above_threshold() {
	mut big := []u8{len: 2048, init: u8(0x41)}
	packets := [big]
	encoded := encode_batch(packets, true, 256)!
	assert encoded[0] == game_packet_header
	assert encoded[1] == compression_zlib
	assert encoded.len < 1 + 1 + big.len
	decoded := decode_batch(encoded, true)!
	assert decoded.len == 1
	assert decoded[0] == big
}

fn test_decode_rejects_bad_header() {
	bad := [u8(0x00), 0x01]
	if _ := decode_batch(bad, false) {
		assert false
	}
}
