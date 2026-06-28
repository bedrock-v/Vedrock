module session

import src as protocol
import src.enums
import src.serializer

fn roundtrip_packet(p protocol.Packet) !protocol.Packet {
	mut pool := protocol.new_packet_pool()
	encoded := protocol.encode_packet_to_bytes(p)
	mut r := serializer.new_reader(encoded)
	return pool.decode(mut r)!
}

fn test_allocate_runtime_id_unique() {
	mut hub := new_hub()
	first := hub.allocate_runtime_id()
	second := hub.allocate_runtime_id()
	third := hub.allocate_runtime_id()
	assert first == 1
	assert second == 2
	assert third == 3
	assert hub.count() == 0
}

fn test_chat_text_packet_roundtrip() {
	decoded := roundtrip_packet(&protocol.TextPacket{
		@type:       int(enums.TextType.chat)
		source_name: 'Steve'
		message:     'hello world'
	})!
	assert decoded.name() == 'TextPacket'
	if decoded is protocol.TextPacket {
		assert decoded.@type == int(enums.TextType.chat)
		assert decoded.source_name == 'Steve'
		assert decoded.message == 'hello world'
	} else {
		assert false
	}
}

fn test_raw_text_packet_roundtrip() {
	decoded := roundtrip_packet(&protocol.TextPacket{
		@type:   int(enums.TextType.raw)
		message: '§eSteve joined the game'
	})!
	if decoded is protocol.TextPacket {
		assert decoded.message == '§eSteve joined the game'
	} else {
		assert false
	}
}

fn test_update_abilities_roundtrip() {
	layer := build_ability_layer(true)
	decoded := roundtrip_packet(&protocol.UpdateAbilitiesPacket{
		data: protocol.AbilitiesData{
			target_actor_unique_id: 7
			player_permission:      2
			command_permission:     0
			layers:                 [layer]
		}
	})!
	assert decoded.name() == 'UpdateAbilitiesPacket'
	if decoded is protocol.UpdateAbilitiesPacket {
		assert decoded.data.target_actor_unique_id == 7
		assert decoded.data.layers.len == 1
		assert decoded.data.layers[0].set_ability_values & ability_bit(ability_may_fly) != 0
	} else {
		assert false
	}
}

fn test_set_time_packet_roundtrip() {
	decoded := roundtrip_packet(&protocol.SetTimePacket{
		time: 6000
	})!
	assert decoded.name() == 'SetTimePacket'
	if decoded is protocol.SetTimePacket {
		assert decoded.time == 6000
	} else {
		assert false
	}
}
