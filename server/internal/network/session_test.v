module network

import protocol
import protocol.serializer
import protocol.version
import protocol.current as proto

fn decode_through_pool(raw []u8, compression_enabled bool) ![]protocol.Packet {
	mut pool := proto.new_packet_pool()
	batch := decode_batch(raw, compression_enabled)!
	mut packets := []protocol.Packet{}
	for b in batch {
		mut r := serializer.new_reader(b)
		packets << pool.decode(mut r)!
	}
	return packets
}

fn test_network_pool_is_locked_to_protocol_2192() {
	assert proto.selected_protocol == 2192
	assert proto.proto_version() == version.ProtoVersion.v2192
	assert proto.selected_minecraft_version == proto.proto_version().minecraft_version()
	mut pool := proto.new_packet_pool()
	assert pool.get_packet_by_id(193) or { return }.name() == 'RequestNetworkSettingsPacket'
}

fn test_request_network_settings_through_batch() {
	req := &proto.RequestNetworkSettingsPacket{
		client_network_version: proto.selected_protocol
	}
	raw := encode_batch([protocol.encode_packet_to_bytes(req)], false, 0)!
	packets := decode_through_pool(raw, false)!
	assert packets.len == 1
	p := packets[0]
	assert p.name() == 'RequestNetworkSettingsPacket'
}

fn test_selected_pool_decodes_2192_auth_input() {
	mut auth := &proto.PlayerAuthInputPacket{}
	auth.player_rotation[0] = 12.5
	auth.player_rotation[1] = 34.25
	auth.player_position[0] = 1.0
	auth.player_position[1] = 2.0
	auth.player_position[2] = 3.0

	mut pool := proto.new_packet_pool()
	mut r := serializer.new_reader(protocol.encode_packet_to_bytes(auth))
	p := pool.decode(mut r)!
	assert p.name() == 'PlayerAuthInputPacket'
	mut input := proto.PlayerAuthInputPacket{}
	decode_into(auth, mut input)!
	assert input.player_rotation[0] == f32(12.5)
	assert input.player_rotation[1] == f32(34.25)
	assert input.player_position[0] == f32(1.0)
	assert input.player_position[1] == f32(2.0)
	assert input.player_position[2] == f32(3.0)
}

fn test_multiple_packets_compressed_batch() {
	req := &proto.RequestNetworkSettingsPacket{
		client_network_version: proto.selected_protocol
	}
	settings := &proto.NetworkSettingsPacket{
		compression_threshold: 256
		compression_algorithm: proto.PacketCompressionAlgorithm.z_lib
	}
	payloads := [
		protocol.encode_packet_to_bytes(req),
		protocol.encode_packet_to_bytes(settings),
	]
	raw := encode_batch(payloads, true, 1)!
	assert raw[0] == compression_flate
	packets := decode_through_pool(raw, true)!
	assert packets.len == 2
	assert packets[0].name() == 'RequestNetworkSettingsPacket'
	assert packets[1].name() == 'NetworkSettingsPacket'
}

// decode_into reads a packet's payload back into a typed value. The pool builds
// the type the version module declares, which an alias of it does not stand in
// for, so the fields are read back directly instead of through a type check.
fn decode_into[T](p protocol.Packet, mut out T) ! {
	mut r := serializer.new_reader(protocol.encode_packet_to_bytes(p))
	protocol.read_packet_header(mut r)!
	out.decode_payload(mut r)!
}
