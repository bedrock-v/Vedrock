module session

import bedrock_v.protocol
import bedrock_v.protocol.serializer
import server.internal.gamedata
import server.player
import server.internal.auth
import server.effect
import server.worldrt
import time
import bedrock_v.protocol.current as proto

fn roundtrip_packet(p protocol.Packet) !protocol.Packet {
	mut pool := proto.new_packet_pool()
	encoded := protocol.encode_packet_to_bytes(p)
	mut r := serializer.new_reader(encoded)
	return pool.decode(mut r)!
}

// decode_into reads a packet's payload back into a typed value. The pool builds
// the type the version module declares, which an alias of it does not stand in
// for, so the fields are read back directly instead of through a type check.
fn decode_into[T](p protocol.Packet, mut out T) ! {
	mut r := serializer.new_reader(protocol.encode_packet_to_bytes(p))
	protocol.read_packet_header(mut r)!
	out.decode_payload(mut r)!
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
	sent := &proto.TextPacket{
		message_type: proto.TextChat{
			player_name: 'Steve'
			message:     'hello world'
		}
	}
	assert roundtrip_packet(sent)!.name() == 'TextPacket'
	mut decoded := proto.TextPacket{}
	decode_into(sent, mut decoded)!
	if message := proto.text_chat(decoded.message_type) {
		assert message.player_name == 'Steve'
		assert message.message == 'hello world'
	} else {
		assert false
	}
}

fn test_raw_text_packet_roundtrip() {
	sent := &proto.TextPacket{
		message_type: proto.TextRaw{
			message: '§eSteve joined the game'
		}
	}
	roundtrip_packet(sent)!
	mut decoded := proto.TextPacket{}
	decode_into(sent, mut decoded)!
	if message := proto.text_raw(decoded.message_type) {
		assert message.message == '§eSteve joined the game'
	} else {
		assert false
	}
}

fn test_update_abilities_roundtrip() {
	mut s := named_session('Alex', 7)
	s.player.set_game_mode(.creative)
	sent := &proto.UpdateAbilitiesPacket{
		data: s.build_abilities()
	}
	assert roundtrip_packet(sent)!.name() == 'UpdateAbilitiesPacket'
	mut decoded := proto.UpdateAbilitiesPacket{}
	decode_into(sent, mut decoded)!
	// A session's own abilities name it by the self id, not by its server
	// wide runtime id.
	assert decoded.data.target_player_raw_id == i64(self_entity_runtime_id)
	assert decoded.data.layers.len == 1
	assert decoded.data.layers[0].ability_values & ability_bit(proto.ability_may_fly) != 0
}

fn test_block_update_flags_match_reference_servers() {
	assert worldrt.block_update_flags == 11
}

fn test_mob_effect_packet_roundtrip() {
	mut s := named_session('Alex', 7)
	sent := s.mob_effect_packet(s.player, effect.new(effect.regeneration, 2, 5 * time.second),
		proto.MobEffectEvent.add)
	assert roundtrip_packet(sent)!.name() == 'MobEffectPacket'
	mut decoded := proto.MobEffectPacket{}
	decode_into(sent, mut decoded)!
	assert decoded.target_runtime_id.value == self_entity_runtime_id
	assert decoded.event_id == proto.MobEffectEvent.add
	assert decoded.effect_id == effect.regeneration.id
	assert decoded.effect_amplifier == 1
	assert decoded.effect_duration_ticks == 100
}

fn test_player_list_add_roundtrip_with_skin() {
	sent := &proto.PlayerListPacket{
		entries: [
			proto.PlayerListAdd{
				entry: proto.AddPlayerListEntry{
					uuid:            proto.uuid_from_bytes(seed_uuid(5))
					target_actor_id: proto.actor_unique_id(5)
					player_name:     'Steve'
					build_platform:  .unknown
					serialized_skin: default_skin('Steve')
					color:           proto.Color{
						r: -1
						g: -1
						b: -1
						a: -1
					}
				}
			},
		]
	}
	assert roundtrip_packet(sent)!.name() == 'PlayerListPacket'
	mut decoded := proto.PlayerListPacket{}
	decode_into(sent, mut decoded)!
	assert decoded.entries.len == 1
	entry := decoded.entries[0]
	if added := proto.player_list_add(entry) {
		assert added.entry.player_name == 'Steve'
		assert added.entry.serialized_skin.skin_image_width == skin_width
	} else {
		assert false
	}
}

fn named_session(name string, runtime_id u64) &NetworkSession {
	mut s := &NetworkSession{
		player:     &player.Player{
			identity: auth.Identity{
				display_name: name
			}
		}
		runtime_id: runtime_id
	}
	s.player.sink = s
	s.player.runtime_id = runtime_id
	return s
}

fn test_add_player_roundtrip() {
	mut subject := named_session('Alex', 9)
	mut viewer := named_session('Bob', 4)

	sent := viewer.add_player_packet(subject.player)
	assert roundtrip_packet(sent)!.name() == 'AddPlayerPacket'
	mut decoded := proto.AddPlayerPacket{}
	decode_into(sent, mut decoded)!
	assert decoded.player_name == 'Alex'
	assert decoded.target_runtime_id.value == self_entity_runtime_id + 1
}

fn test_runtime_ids_are_per_viewer() {
	mut subject := named_session('Alex', 9)
	mut first := named_session('Bob', 4)
	mut second := named_session('Cara', 7)

	// second has already been shown someone else, so its numbering has moved
	// on before it ever sees subject.
	second.wire_id_for(4)

	assert first.wire_id_for(subject.runtime_id) != second.wire_id_for(subject.runtime_id)
	assert first.wire_id_for(first.runtime_id) == self_entity_runtime_id
	assert second.wire_id_for(second.runtime_id) == self_entity_runtime_id
	// Asking twice hands back the same number or a client would see the
	// player it is watching jump to a new actor every packet.
	assert first.wire_id_for(subject.runtime_id) == first.wire_id_for(subject.runtime_id)
	// A world change drops the numbering; it means nothing on the other side.
	before := first.wire_id_for(subject.runtime_id)
	first.forget_wire_ids()
	assert first.wire_id_for(99) == before
}

fn test_add_player_visible_nametag_metadata() {
	mut subject := named_session('Alex', 9)
	mut viewer := named_session('Bob', 4)
	p := viewer.add_player_packet(subject.player)
	assert p.entity_data.len == 9
	assert p.entity_data[0].data_item_id == proto.meta_key_flags
	assert p.entity_data[2].data_item_id == proto.meta_key_name
	assert p.entity_data[8].data_item_id == proto.meta_key_always_show_name_tag
	if value := proto.data_item_string(p.entity_data[2].data_item_type) {
		assert value.value == 'Alex'
	} else {
		assert false
	}
	if value := proto.data_item_byte(p.entity_data[8].data_item_type) {
		assert value.value == 1
	} else {
		assert false
	}
}

fn test_move_and_remove_roundtrip() {
	mut move_packet := &proto.MovePlayerPacket{
		player_runtime_id: proto.actor_runtime_id(3)
		on_ground:         true
	}
	move_packet.position[0] = 1.0
	move_packet.position[1] = 65.0
	move_packet.position[2] = 2.0
	move := roundtrip_packet(move_packet)!
	assert move.name() == 'MovePlayerPacket'
	remove := roundtrip_packet(&proto.RemoveActorPacket{
		target_actor_id: proto.actor_unique_id(3)
	})!
	assert remove.name() == 'RemoveActorPacket'
}

fn test_set_time_packet_roundtrip() {
	sent := &proto.SetTimePacket{
		time: 6000
	}
	assert roundtrip_packet(sent)!.name() == 'SetTimePacket'
	mut decoded := proto.SetTimePacket{}
	decode_into(sent, mut decoded)!
	assert decoded.time == 6000
}
