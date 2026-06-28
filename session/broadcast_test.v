module session

import protocol
import protocol.enums
import protocol.types
import protocol.serializer
import gamedata

fn roundtrip_packet(p protocol.Packet) !protocol.Packet {
	mut pool := protocol.new_packet_pool()
	encoded := protocol.encode_packet_to_bytes(p)
	mut r := serializer.new_reader(encoded)
	return pool.decode(mut r)!
}

fn test_allocate_runtime_id_unique() {
	mut hub := new_hub(gamedata.GameData{})
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

fn test_player_list_add_roundtrip_with_skin() {
	decoded := roundtrip_packet(&protocol.PlayerListPacket{
		type:    protocol.player_list_type_add
		entries: [
			protocol.PlayerListEntry{
				uuid:            types.uuid_from_bytes(seed_uuid(5))
				actor_unique_id: 5
				username:        'Steve'
				build_platform:  -1
				skin:            default_skin('Steve')
				color:           0xffffffff
				verified:        true
			},
		]
	})!
	assert decoded.name() == 'PlayerListPacket'
	if decoded is protocol.PlayerListPacket {
		assert decoded.entries.len == 1
		assert decoded.entries[0].username == 'Steve'
		assert decoded.entries[0].skin.skin_image.width == skin_width
	} else {
		assert false
	}
}

fn test_add_player_roundtrip() {
	decoded := roundtrip_packet(&protocol.AddPlayerPacket{
		uuid:              types.uuid_from_bytes(seed_uuid(9))
		username:          'Alex'
		actor_runtime_id:  9
		position:          types.Vector3{0.0, 64.0, 0.0}
		game_mode:         1
		metadata:          []types.MetadataEntry{}
		synced_properties: types.PropertySyncData{}
		abilities:         protocol.AbilitiesData{
			layers: [build_ability_layer(true)]
		}
		links:             []types.EntityLink{}
		build_platform:    -1
	})!
	assert decoded.name() == 'AddPlayerPacket'
	if decoded is protocol.AddPlayerPacket {
		assert decoded.username == 'Alex'
		assert decoded.actor_runtime_id == 9
	} else {
		assert false
	}
}

fn test_move_and_remove_roundtrip() {
	move := roundtrip_packet(&protocol.MovePlayerPacket{
		actor_runtime_id: 3
		position:         types.Vector3{1.0, 65.0, 2.0}
		on_ground:        true
	})!
	assert move.name() == 'MovePlayerPacket'
	remove := roundtrip_packet(&protocol.RemoveActorPacket{
		actor_unique_id: 3
	})!
	assert remove.name() == 'RemoveActorPacket'
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
