module session

import src as protocol
import src.types
import src.serializer

fn test_empty_chunk_payload_layout() {
	payload := empty_chunk_payload()
	assert payload.len == overworld_subchunk_count * 2 + 1
	for i in 0 .. overworld_subchunk_count {
		assert payload[i * 2] == 0x01
		assert payload[i * 2 + 1] == plains_biome_id << 1
	}
	assert payload[payload.len - 1] == 0x00
}

fn test_level_chunk_roundtrip_preserves_payload() {
	payload := empty_chunk_payload().bytestr()
	mut pool := protocol.new_packet_pool()
	packet := &protocol.LevelChunkPacket{
		chunk_position:  types.ChunkPosition{3, -5}
		dimension_id:    0
		request_type:    protocol.level_chunk_request_explicit
		sub_chunk_count: 0
		cache_enabled:   false
		extra_payload:   payload
	}
	encoded := protocol.encode_packet_to_bytes(packet)
	mut r := serializer.new_reader(encoded)
	decoded := pool.decode(mut r)!
	assert decoded.name() == 'LevelChunkPacket'
	if decoded is protocol.LevelChunkPacket {
		assert decoded.chunk_position.x == 3
		assert decoded.chunk_position.z == -5
		assert decoded.sub_chunk_count == 0
		assert decoded.extra_payload.len == payload.len
		assert decoded.extra_payload == payload
	} else {
		assert false
	}
}
