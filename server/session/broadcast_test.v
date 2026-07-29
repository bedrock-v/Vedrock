module session

import protocol
import protocol.version.v662.packets as packets_662
import protocol.version.v662.types as types_662
import protocol.version.v776.packets as packets_776
import protocol.version.v800.packets as packets_800
import protocol.version.v800.types as types_800
import protocol.version.v898.packets as packets_898
import protocol.version.v924.enums as enums_924
import protocol.version.v924.packets as packets_924
import protocol.serializer
import server.internal.gamedata
import server.internal.network
import server.player
import server.internal.auth
import server.effect
import time

fn roundtrip_packet(p protocol.Packet) !protocol.Packet {
	mut pool := network.new_selected_packet_pool()
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

fn test_session_by_name_case_insensitive() {
	mut hub := new_hub(gamedata.GameData{})
	steve := &NetworkSession{
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Steve'
			}
		}
		runtime_id: 1
	}
	alex := &NetworkSession{
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		runtime_id: 2
	}
	hub.add(steve)
	hub.add(alex)

	found := hub.session_by_name('alex') or { panic('expected to find Alex') }
	assert found.runtime_id == 2

	if _ := hub.session_by_name('ghost') {
		assert false
	}
}

fn test_chat_text_packet_roundtrip() {
	decoded := roundtrip_packet(&packets_924.TextPacket{
		message_type: enums_924.TextChat{
			player_name: 'Steve'
			message:     'hello world'
		}
	})!
	assert decoded.name() == 'TextPacket'
	if decoded is packets_924.TextPacket {
		match decoded.message_type {
			enums_924.TextChat {
				message := decoded.message_type
				assert message.player_name == 'Steve'
				assert message.message == 'hello world'
			}
			else {
				assert false
			}
		}
	} else {
		assert false
	}
}

fn test_raw_text_packet_roundtrip() {
	decoded := roundtrip_packet(&packets_924.TextPacket{
		message_type: enums_924.TextRaw{
			message: '§eSteve joined the game'
		}
	})!
	if decoded is packets_924.TextPacket {
		match decoded.message_type {
			enums_924.TextRaw {
				message := decoded.message_type
				assert message.message == '§eSteve joined the game'
			}
			else {
				assert false
			}
		}
	} else {
		assert false
	}
}

fn test_update_abilities_roundtrip() {
	mut s := &NetworkSession{
		player:     player.new_player()
		runtime_id: 7
	}
	s.player.set_game_mode(network.game_type_creative)
	decoded := roundtrip_packet(&packets_776.UpdateAbilitiesPacket{
		data: s.build_abilities_776()
	})!
	assert decoded.name() == 'UpdateAbilitiesPacket'
	if decoded is packets_776.UpdateAbilitiesPacket {
		assert decoded.data.target_player_raw_id == 7
		assert decoded.data.layers.len == 1
		assert decoded.data.layers[0].ability_values & ability_bit(network.ability_may_fly) != 0
	} else {
		assert false
	}
}

fn test_block_update_flags_match_reference_servers() {
	assert block_update_flags == 11
}

fn test_mob_effect_packet_roundtrip() {
	s := &NetworkSession{
		player:     player.new_player()
		runtime_id: 7
	}
	decoded := roundtrip_packet(s.mob_effect_packet(effect.new(effect.regeneration, 2,
		5 * time.second), mob_effect_add))!
	assert decoded.name() == 'MobEffectPacket'
	if decoded is packets_898.MobEffectPacket {
		assert decoded.target_runtime_id.value == 7
		assert decoded.event_id == mob_effect_add
		assert decoded.effect_id == effect.regeneration.id
		assert decoded.effect_amplifier == 1
		assert decoded.effect_duration_ticks == 100
	} else {
		assert false
	}
}

fn test_player_list_add_roundtrip_with_skin() {
	decoded := roundtrip_packet(&packets_800.PlayerListPacket{
		action: packets_800.PlayerListAdd{
			add_player_list: [
				packets_800.AddPlayerListEntry{
					uuid:            network.uuid_from_bytes(seed_uuid(5))
					target_actor_id: network.actor_unique_id(5)
					player_name:     'Steve'
					build_platform:  .unknown
					serialized_skin: default_skin('Steve')
					color:           types_800.Color{
						r: -1
						g: -1
						b: -1
						a: -1
					}
				},
			]
			is_trusted_skin: [true]
		}
	})!
	assert decoded.name() == 'PlayerListPacket'
	if decoded is packets_800.PlayerListPacket {
		match decoded.action {
			packets_800.PlayerListAdd {
				action := decoded.action
				assert action.add_player_list.len == 1
				assert action.add_player_list[0].player_name == 'Steve'
				assert action.add_player_list[0].serialized_skin.skin_image_width == skin_width
			}
			packets_800.PlayerListRemove {
				assert false
			}
		}
	} else {
		assert false
	}
}

fn test_add_player_roundtrip() {
	s := &NetworkSession{
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		runtime_id: 9
	}
	decoded := roundtrip_packet(s.add_player_packet())!
	assert decoded.name() == 'AddPlayerPacket'
	if decoded is packets_776.AddPlayerPacket {
		assert decoded.player_name == 'Alex'
		assert decoded.target_runtime_id.value == 9
	} else {
		assert false
	}
}

fn test_add_player_visible_nametag_metadata() {
	s := &NetworkSession{
		player:     &player.Player{
			identity: auth.Identity{
				display_name: 'Alex'
			}
		}
		runtime_id: 9
	}
	p := s.add_player_packet()
	assert p.entity_data.len == 9
	assert p.entity_data[0].data_item_id == network.meta_key_flags
	assert p.entity_data[2].data_item_id == network.meta_key_name
	assert p.entity_data[8].data_item_id == network.meta_key_always_show_name_tag
	match p.entity_data[2].data_item_type {
		types_662.DataItemString {
			value := p.entity_data[2].data_item_type
			assert value.value == 'Alex'
		}
		else {
			assert false
		}
	}
	match p.entity_data[8].data_item_type {
		types_662.DataItemByte {
			value := p.entity_data[8].data_item_type
			assert value.value == 1
		}
		else {
			assert false
		}
	}
}

fn test_move_and_remove_roundtrip() {
	mut move_packet := &packets_662.MovePlayerPacket{
		player_runtime_id: network.actor_runtime_id(3)
		on_ground:         true
	}
	move_packet.position[0] = 1.0
	move_packet.position[1] = 65.0
	move_packet.position[2] = 2.0
	move := roundtrip_packet(move_packet)!
	assert move.name() == 'MovePlayerPacket'
	remove := roundtrip_packet(&packets_662.RemoveActorPacket{
		target_actor_id: network.actor_unique_id(3)
	})!
	assert remove.name() == 'RemoveActorPacket'
}

fn test_set_time_packet_roundtrip() {
	decoded := roundtrip_packet(&packets_662.SetTimePacket{
		time: 6000
	})!
	assert decoded.name() == 'SetTimePacket'
	if decoded is packets_662.SetTimePacket {
		assert decoded.time == 6000
	} else {
		assert false
	}
}
