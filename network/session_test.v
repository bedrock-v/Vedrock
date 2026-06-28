module network

import protocol
import protocol.serializer

fn decode_through_pool(raw []u8, compression_enabled bool) ![]protocol.Packet {
	mut pool := protocol.new_packet_pool()
	batch := decode_batch(raw, compression_enabled)!
	mut packets := []protocol.Packet{}
	for b in batch {
		mut r := serializer.new_reader(b)
		packets << pool.decode(mut r)!
	}
	return packets
}

fn test_request_network_settings_through_batch() {
	req := &protocol.RequestNetworkSettingsPacket{
		protocol_version: protocol.current_protocol
	}
	raw := encode_batch([protocol.encode_packet_to_bytes(req)], false, 0)!
	packets := decode_through_pool(raw, false)!
	assert packets.len == 1
	p := packets[0]
	assert p.name() == 'RequestNetworkSettingsPacket'
	if p is protocol.RequestNetworkSettingsPacket {
		assert p.protocol_version == protocol.current_protocol
	} else {
		assert false
	}
}

fn test_multiple_packets_compressed_batch() {
	req := &protocol.RequestNetworkSettingsPacket{
		protocol_version: protocol.current_protocol
	}
	settings := &protocol.NetworkSettingsPacket{
		compression_threshold: 256
		compression_algorithm: 0
	}
	payloads := [
		protocol.encode_packet_to_bytes(req),
		protocol.encode_packet_to_bytes(settings),
	]
	raw := encode_batch(payloads, true, 1)!
	assert raw[1] == compression_zlib
	packets := decode_through_pool(raw, true)!
	assert packets.len == 2
	assert packets[0].name() == 'RequestNetworkSettingsPacket'
	assert packets[1].name() == 'NetworkSettingsPacket'
}
