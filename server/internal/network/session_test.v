module network

import protocol
import protocol.serializer
import protocol.version
import protocol.version.v662.enums as enums_662
import protocol.version.v662.packets as packets_662
import protocol.types as model
import protocol.version.v2192.packets as packets_2192

fn decode_through_pool(raw []u8, compression_enabled bool) ![]protocol.Packet {
	mut pool := new_selected_packet_pool()
	batch := decode_batch(raw, compression_enabled)!
	mut packets := []protocol.Packet{}
	for b in batch {
		mut r := serializer.new_reader(b)
		packets << pool.decode(mut r)!
	}
	return packets
}

fn test_network_pool_is_locked_to_protocol_2192() {
	assert selected_protocol == 2192
	assert selected_proto_version() == version.ProtoVersion.v2192
	assert selected_minecraft_version == selected_proto_version().minecraft_version()
	mut pool := new_selected_packet_pool()
	assert pool.get_packet_by_id(193) or { return }.name() == 'RequestNetworkSettingsPacket'
}

fn test_request_network_settings_through_batch() {
	req := &packets_662.RequestNetworkSettingsPacket{
		client_network_version: selected_protocol
	}
	raw := encode_batch([protocol.encode_packet_to_bytes(req)], false, 0)!
	packets := decode_through_pool(raw, false)!
	assert packets.len == 1
	p := packets[0]
	assert p.name() == 'RequestNetworkSettingsPacket'
}

fn test_selected_pool_decodes_2192_auth_input() {
	mut auth := &packets_2192.PlayerAuthInputPacket{}
	auth.player_rotation[0] = 12.5
	auth.player_rotation[1] = 34.25
	auth.player_position[0] = 1.0
	auth.player_position[1] = 2.0
	auth.player_position[2] = 3.0

	mut pool := new_selected_packet_pool()
	mut r := serializer.new_reader(protocol.encode_packet_to_bytes(auth))
	p := pool.decode(mut r)!
	assert p.name() == 'PlayerAuthInputPacket'
	if p is packets_2192.PlayerAuthInputPacket {
		assert p.player_rotation[0] == f32(12.5)
		assert p.player_rotation[1] == f32(34.25)
		assert p.player_position[0] == f32(1.0)
		assert p.player_position[1] == f32(2.0)
		assert p.player_position[2] == f32(3.0)
	} else {
		assert false, 'decoded packet is not PlayerAuthInputPacket'
	}
}

fn item_instance_extra_data_len(item model.ItemStack) !int {
	mut w := serializer.new_writer()
	item_instance_v2168(item).encode(mut w)
	mut r := serializer.new_reader(w.bytes())
	r.read_varint32()!
	r.le_u16()!
	r.read_varuint32()!
	r.read_varint32()!
	return r.read_string_bytes()!.len
}

fn item_descriptor_v2_extra_data_len(item model.ItemStack) !int {
	mut w := serializer.new_writer()
	item_descriptor_v2168_v2(item).encode(mut w)
	mut r := serializer.new_reader(w.bytes())
	r.le_i16()!
	r.le_u16()!
	r.read_varuint32()!
	if r.bool()! {
		r.read_varuint32()!
		r.read_varint32()!
	}
	r.read_varuint32()!
	return r.read_string_bytes()!.len
}

fn test_v2168_shield_writes_blocking_ticks_extra_data() {
	assert item_instance_extra_data_len(model.ItemStack{ id: shield_runtime_id_v2168, count: 1 })! == 18
	assert item_descriptor_v2_extra_data_len(model.ItemStack{ id: shield_runtime_id_v2168, count: 1 })! == 18
	assert item_instance_extra_data_len(model.ItemStack{ id: 1, count: 1 })! == 10
}

fn test_multiple_packets_compressed_batch() {
	req := &packets_662.RequestNetworkSettingsPacket{
		client_network_version: selected_protocol
	}
	settings := &packets_662.NetworkSettingsPacket{
		compression_threshold: 256
		compression_algorithm: enums_662.PacketCompressionAlgorithm.z_lib
	}
	payloads := [
		protocol.encode_packet_to_bytes(req),
		protocol.encode_packet_to_bytes(settings),
	]
	raw := encode_batch(payloads, true, 1)!
	assert raw[1] == compression_flate
	packets := decode_through_pool(raw, true)!
	assert packets.len == 2
	assert packets[0].name() == 'RequestNetworkSettingsPacket'
	assert packets[1].name() == 'NetworkSettingsPacket'
}
