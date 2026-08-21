module session

import protocol.current as proto

const skin_width = u32(64)
const skin_height = u32(64)

fn hex_value(c u8) int {
	if c >= `0` && c <= `9` {
		return int(c - `0`)
	}
	if c >= `a` && c <= `f` {
		return int(c - `a`) + 10
	}
	if c >= `A` && c <= `F` {
		return int(c - `A`) + 10
	}
	return -1
}

fn seed_uuid(seed u64) []u8 {
	mut out := []u8{len: 16}
	for i in 0 .. 8 {
		out[8 + i] = u8((seed >> u64(8 * i)) & 0xff)
	}
	out[6] = 0x40
	out[8] = 0x80
	return out
}

fn parse_uuid(value string, seed u64) []u8 {
	clean := value.replace('-', '')
	if clean.len != 32 {
		return seed_uuid(seed)
	}
	mut out := []u8{len: 16}
	for i in 0 .. 16 {
		hi := hex_value(clean[i * 2])
		lo := hex_value(clean[i * 2 + 1])
		if hi < 0 || lo < 0 {
			return seed_uuid(seed)
		}
		out[i] = u8(hi * 16 + lo)
	}
	return out
}

fn (s &NetworkSession) uuid() proto.Uuid {
	return proto.uuid_from_bytes(parse_uuid(s.player.identity.uuid, s.runtime_id))
}

fn default_skin(id string) proto.SerializedSkin {
	pixels := []u8{len: int(skin_width * skin_height * 4), init: u8(0xff)}
	return proto.SerializedSkin{
		skin_id:                         '${id}.Vedrock'
		play_fab_id:                     ''
		skin_resource_patch:             '{"geometry":{"default":"geometry.humanoid.custom"}}'
		skin_image_width:                skin_width
		skin_image_height:               skin_height
		skin_image_bytes:                pixels
		animations:                      []proto.SerializedSkinAnimationFrame{}
		cape_image_width:                0
		cape_image_height:               0
		cape_image_bytes:                []u8{}
		geometry_data:                   '{}'
		geometry_data_engine_version:    ''
		animation_data:                  ''
		cape_id:                         ''
		full_id:                         '${id}.Vedrock'
		arm_size:                        proto.ArmSizeType.wide
		skin_color:                      0
		persona_pieces:                  []proto.PersonaPiecesEntry{}
		piece_tint_colors:               []proto.PieceTintColorsEntry{}
		is_premium_skin:                 false
		is_persona_skin:                 false
		is_persona_cape_on_classic_skin: false
		is_primary_user:                 true
		overrides_player_appearance:     true
		trusted_skin_flag:               'true'
		profile_hash:                    ''
	}
}

fn (s &NetworkSession) player_list_add_packet() &proto.PlayerListPacket {
	return &proto.PlayerListPacket{
		entries: [
			proto.PlayerListAdd{
				entry: proto.AddPlayerListEntry{
					uuid:             s.uuid()
					target_actor_id:  proto.actor_unique_id(i64(s.runtime_id))
					player_name:      s.player.identity.display_name
					xbl_xuid:         s.player.identity.xuid
					platform_chat_id: ''
					build_platform:   proto.BuildPlatform.unknown
					serialized_skin:  default_skin(s.player.identity.display_name)
					is_teacher:       false
					is_host:          false
					is_sub_client:    false
					color:            proto.Color{
						r: -1
						g: -1
						b: -1
						a: -1
					}
				}
			},
		]
	}
}

fn (s &NetworkSession) player_list_remove_packet() &proto.PlayerListPacket {
	return &proto.PlayerListPacket{
		entries: [
			proto.PlayerListRemove{
				uuid: s.uuid()
			},
		]
	}
}

fn (s &NetworkSession) add_player_packet() &proto.AddPlayerPacket {
	current := s.player.movement()
	mut packet := &proto.AddPlayerPacket{
		uuid:              s.uuid()
		player_name:       s.player.identity.display_name
		target_runtime_id: proto.actor_runtime_id(s.runtime_id)
		platform_chat_id:  ''
		y_head_rotation:   current.head_yaw
		carried_item:      proto.item_descriptor(s.player.held_item().item_stack)
		player_game_type:  proto.game_type(s.player.game_mode())
		entity_data:       visible_name_metadata(s.player.identity.display_name)
		synced_properties: proto.PropertySyncData{}
		abilities_data:    s.build_abilities()
		actor_links:       []proto.ActorLink{}
		device_id:         ''
		build_platform:    proto.BuildPlatform.unknown
	}
	packet.position[0] = current.position.x
	packet.position[1] = current.position.y
	packet.position[2] = current.position.z
	packet.velocity[0] = 0.0
	packet.velocity[1] = 0.0
	packet.velocity[2] = 0.0
	packet.rotation[0] = current.pitch
	packet.rotation[1] = current.yaw
	return packet
}

fn (s &NetworkSession) move_actor_packet() &proto.MoveActorAbsolutePacket {
	current := s.player.movement()
	return &proto.MoveActorAbsolutePacket{
		move_data: proto.MoveActorAbsoluteData{
			actor_runtime_id: proto.actor_runtime_id(s.runtime_id)
			header:           i8(proto.move_actor_flag_on_ground)
			position_x:       current.position.x
			position_y:       current.position.y
			position_z:       current.position.z
			rotation_x:       proto.rotation_byte(current.pitch)
			rotation_y:       proto.rotation_byte(current.yaw)
			rotation_y_head:  proto.rotation_byte(current.head_yaw)
		}
	}
}

fn (s &NetworkSession) remove_actor_packet() &proto.RemoveActorPacket {
	return &proto.RemoveActorPacket{
		target_actor_id: proto.actor_unique_id(i64(s.runtime_id))
	}
}
