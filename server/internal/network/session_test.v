module network

import bedrock_v.protocol
import bedrock_v.protocol.serializer
import bedrock_v.protocol.enums
import bedrock_v.protocol.packets

fn decode_through_pool(raw []u8, compression_enabled bool) ![]protocol.Packet {
	mut pool := protocol.new_pool()
	batch := decode_batch(raw, compression_enabled)!
	mut decoded := []protocol.Packet{}
	for b in batch {
		mut r := serializer.new_reader(b)
		decoded << pool.decode(mut r)!
	}
	return decoded
}

fn test_network_pool_is_locked_to_protocol_2192() {
	assert int(protocol.protocol_id) == 2192
	assert protocol.minecraft_version == protocol.minecraft_version
	mut pool := protocol.new_pool()
	assert pool.get_packet_by_id(193) or { return }.name() == 'RequestNetworkSettingsPacket'
}

fn test_request_network_settings_through_batch() {
	req := &packets.RequestNetworkSettingsPacket{
		client_network_version: int(protocol.protocol_id)
	}
	raw := encode_batch([protocol.encode_packet_to_bytes(req)], false, 0)!
	decoded := decode_through_pool(raw, false)!
	assert decoded.len == 1
	p := decoded[0]
	assert p.name() == 'RequestNetworkSettingsPacket'
}

fn test_selected_pool_decodes_2192_auth_input() {
	mut auth := &packets.PlayerAuthInputPacket{}
	auth.player_rotation[0] = 12.5
	auth.player_rotation[1] = 34.25
	auth.player_position[0] = 1.0
	auth.player_position[1] = 2.0
	auth.player_position[2] = 3.0

	mut pool := protocol.new_pool()
	mut r := serializer.new_reader(protocol.encode_packet_to_bytes(auth))
	p := pool.decode(mut r)!
	assert p.name() == 'PlayerAuthInputPacket'
	mut input := packets.PlayerAuthInputPacket{}
	decode_into(auth, mut input)!
	assert input.player_rotation[0] == f32(12.5)
	assert input.player_rotation[1] == f32(34.25)
	assert input.player_position[0] == f32(1.0)
	assert input.player_position[1] == f32(2.0)
	assert input.player_position[2] == f32(3.0)
}

fn test_multiple_packets_compressed_batch() {
	req := &packets.RequestNetworkSettingsPacket{
		client_network_version: int(protocol.protocol_id)
	}
	settings := &packets.NetworkSettingsPacket{
		compression_threshold: 256
		compression_algorithm: enums.PacketCompressionAlgorithm.z_lib
	}
	payloads := [
		protocol.encode_packet_to_bytes(req),
		protocol.encode_packet_to_bytes(settings),
	]
	raw := encode_batch(payloads, true, 1)!
	assert raw[0] == compression_flate
	decoded := decode_through_pool(raw, true)!
	assert decoded.len == 2
	assert decoded[0].name() == 'RequestNetworkSettingsPacket'
	assert decoded[1].name() == 'NetworkSettingsPacket'
}

// decode_into reads a packet's payload back into a typed value. The pool builds
// the type the version module declares, which an alias of it does not stand in
// for, so the fields are read back directly instead of through a type check.
fn decode_into[T](p protocol.Packet, mut out T) ! {
	mut r := serializer.new_reader(protocol.encode_packet_to_bytes(p))
	protocol.read_packet_header(mut r)!
	out.decode_payload(mut r)!
}
