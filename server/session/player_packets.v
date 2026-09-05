module session

import bedrock_v.protocol.current as proto
import server.effect
import server.player
import server.player.skin

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

// player_uuid is a player's identity as the client knows it.
fn player_uuid(p &player.Player) proto.Uuid {
	return proto.uuid_from_bytes(parse_uuid(p.identity.uuid, p.runtime_id()))
}

// default_skin builds the plain white skin the server hands out to players
// whose own skin it doesn't track and converts it to the serialized form the
// client expects.
fn default_skin(id string) proto.SerializedSkin {
	mut sk := skin.new(int(skin_width), int(skin_height))
	sk.id = '${id}.Vedrock'
	sk.full_id = '${id}.Vedrock'
	sk.fill(skin.Colour{
		r: 0xff
		g: 0xff
		b: 0xff
		a: 0xff
	})
	return serialize_skin(sk)
}

// serialize_skin converts "sk"in to the packet form of a skin. Fields the skin
// type has no say over, such as the persona pieces, are left at the neutral
// values a server built skin uses.
fn serialize_skin(sk skin.Skin) proto.SerializedSkin {
	mut cape_width := u32(0)
	mut cape_height := u32(0)
	if sk.cape.exists() {
		cape_width = u32(sk.cape.width())
		cape_height = u32(sk.cape.height())
	}
	return proto.SerializedSkin{
		skin_id:                         sk.id
		play_fab_id:                     sk.play_fab_id
		skin_resource_patch:             sk.model_config.encode()
		skin_image_width:                u32(sk.width())
		skin_image_height:               u32(sk.height())
		skin_image_bytes:                sk.pix
		animations:                      []proto.SerializedSkinAnimationFrame{}
		cape_image_width:                cape_width
		cape_image_height:               cape_height
		cape_image_bytes:                sk.cape.pix
		geometry_data:                   if sk.model.len == 0 { '{}' } else { sk.model.bytestr() }
		geometry_data_engine_version:    ''
		animation_data:                  ''
		cape_id:                         sk.cape.id
		full_id:                         sk.full_id
		arm_size:                        proto.ArmSizeType.wide
		skin_color:                      0
		persona_pieces:                  []proto.PersonaPiecesEntry{}
		piece_tint_colors:               []proto.PieceTintColorsEntry{}
		is_premium_skin:                 false
		is_persona_skin:                 sk.persona
		is_persona_cape_on_classic_skin: false
		is_primary_user:                 true
		overrides_player_appearance:     true
		trusted_skin_flag:               'true'
		profile_hash:                    ''
	}
}

fn (mut s NetworkSession) player_list_add_packet(p &player.Player) &proto.PlayerListPacket {
	return &proto.PlayerListPacket{
		entries: [
			proto.PlayerListAdd{
				entry: proto.AddPlayerListEntry{
					uuid:             player_uuid(p)
					target_actor_id:  proto.actor_unique_id(i64(s.wire_id_for(p.runtime_id())))
					player_name:      p.identity.display_name
					xbl_xuid:         p.identity.xuid
					platform_chat_id: ''
					build_platform:   proto.BuildPlatform.unknown
					serialized_skin:  default_skin(p.identity.display_name)
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

fn (mut s NetworkSession) player_list_remove_packet(p &player.Player) &proto.PlayerListPacket {
	return &proto.PlayerListPacket{
		entries: [
			proto.PlayerListRemove{
				uuid: player_uuid(p)
			},
		]
	}
}

fn (mut s NetworkSession) add_player_packet(p &player.Player) &proto.AddPlayerPacket {
	current := p.movement()
	mut packet := &proto.AddPlayerPacket{
		uuid:              player_uuid(p)
		player_name:       p.identity.display_name
		target_runtime_id: proto.actor_runtime_id(s.wire_id_for(p.runtime_id()))
		platform_chat_id:  ''
		y_head_rotation:   current.head_yaw
		carried_item:      proto.item_descriptor(p.held_item().item_stack)
		player_game_type:  proto.game_type(gamemode_to_wire(p.game_mode()))
		entity_data:       visible_name_metadata(p.identity.display_name)
		synced_properties: proto.PropertySyncData{}
		abilities_data:    s.build_abilities_for(p)
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

fn (mut s NetworkSession) remove_actor_packet(p &player.Player) &proto.RemoveActorPacket {
	return &proto.RemoveActorPacket{
		target_actor_id: proto.actor_unique_id(i64(s.wire_id_for(p.runtime_id())))
	}
}

// move_actor_packet is a player's position as other clients see it. It takes
// the player because a viewer builds it for whoever it is being shown.
fn (mut s NetworkSession) move_actor_packet(p &player.Player) &proto.MoveActorAbsolutePacket {
	current := p.movement()
	return &proto.MoveActorAbsolutePacket{
		move_data: proto.MoveActorAbsoluteData{
			actor_runtime_id: proto.actor_runtime_id(s.wire_id_for(p.runtime_id()))
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

// mob_effect_packet is one effect on a player as the clients around them see
// it. Same reason for the parameter as move_actor_packet.
fn (mut s NetworkSession) mob_effect_packet(p &player.Player, e effect.Effect, event_id proto.MobEffectEvent) &proto.MobEffectPacket {
	return &proto.MobEffectPacket{
		target_runtime_id:     proto.actor_runtime_id(s.wire_id_for(p.runtime_id()))
		event_id:              event_id
		effect_id:             e.effect_type().id
		effect_amplifier:      e.level() - 1
		show_particles:        !e.particles_hidden()
		effect_duration_ticks: e.duration_ticks()
		tick:                  u64(e.tick())
		ambient:               e.ambient()
	}
}
