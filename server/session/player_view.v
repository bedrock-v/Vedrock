module session

import protocol
import protocol.types

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

fn (s &NetworkSession) uuid() types.UUID {
	return types.uuid_from_bytes(parse_uuid(s.identity.uuid, s.runtime_id))
}

fn default_skin(id string) types.SkinData {
	pixels := []u8{len: int(skin_width * skin_height * 4), init: u8(0xff)}
	return types.SkinData{
		skin_id:               '${id}.Vedrock'
		play_fab_id:           ''
		resource_patch:        '{"geometry":{"default":"geometry.humanoid.custom"}}'
		skin_image:            types.SkinImage{
			width:  skin_width
			height: skin_height
			data:   pixels.bytestr()
		}
		animations:            []types.SkinAnimation{}
		cape_image:            types.SkinImage{
			width:  0
			height: 0
			data:   ''
		}
		geometry_data:         ''
		geometry_data_version: ''
		animation_data:        ''
		cape_id:               ''
		full_skin_id:          '${id}.Vedrock'
		arm_size:              'wide'
		skin_color:            '#0'
		persona_pieces:        []types.PersonaSkinPiece{}
		piece_tint_colors:     []types.PersonaPieceTintColor{}
		premium:               false
		persona:               false
		cape_on_classic:       false
		is_primary_user:       true
		override:              true
	}
}

fn (s &NetworkSession) player_list_add_packet() &protocol.PlayerListPacket {
	return &protocol.PlayerListPacket{
		type:    protocol.player_list_type_add
		entries: [
			protocol.PlayerListEntry{
				uuid:             s.uuid()
				actor_unique_id:  i64(s.runtime_id)
				username:         s.identity.display_name
				xbox_user_id:     s.identity.xuid
				platform_chat_id: ''
				build_platform:   -1
				skin:             default_skin(s.identity.display_name)
				is_teacher:       false
				is_host:          false
				is_sub_client:    false
				color:            0xffffffff
				verified:         s.identity.xbox_authenticated
			},
		]
	}
}

fn (s &NetworkSession) player_list_remove_packet() &protocol.PlayerListPacket {
	return &protocol.PlayerListPacket{
		type:    protocol.player_list_type_remove
		entries: [
			protocol.PlayerListEntry{
				uuid: s.uuid()
			},
		]
	}
}

fn (s &NetworkSession) add_player_packet() &protocol.AddPlayerPacket {
	return &protocol.AddPlayerPacket{
		uuid:              s.uuid()
		username:          s.identity.display_name
		actor_runtime_id:  s.runtime_id
		platform_chat_id:  ''
		position:          s.position
		motion:            types.Vector3{0.0, 0.0, 0.0}
		pitch:             s.pitch
		yaw:               s.yaw
		head_yaw:          s.head_yaw
		item:              s.held_item
		game_mode:         s.game_mode
		metadata:          visible_name_metadata(s.identity.display_name)
		synced_properties: types.PropertySyncData{}
		abilities:         s.build_abilities()
		links:             []types.EntityLink{}
		device_id:         ''
		build_platform:    -1
	}
}

fn (s &NetworkSession) move_actor_packet() &protocol.MoveActorAbsolutePacket {
	return &protocol.MoveActorAbsolutePacket{
		actor_runtime_id: s.runtime_id
		flags:            protocol.move_actor_flag_on_ground
		position:         s.position
		pitch:            s.pitch
		yaw:              s.yaw
		head_yaw:         s.head_yaw
	}
}

fn (s &NetworkSession) remove_actor_packet() &protocol.RemoveActorPacket {
	return &protocol.RemoveActorPacket{
		actor_unique_id: i64(s.runtime_id)
	}
}
