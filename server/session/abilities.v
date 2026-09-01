module session

import bedrock_v.protocol.current as proto
import server.player

// Bedrock's UpdateAbilitiesPacket.command_permission wire values.
const command_permission_normal = u8(0)
const command_permission_operator = u8(1)

fn ability_bit(index int) u32 {
	return u32(1) << u32(index)
}

fn build_ability_layer(flies bool) proto.SerializedLayer {
	mut values := ability_bit(proto.ability_build) | ability_bit(proto.ability_mine) | ability_bit(proto.ability_doors_and_switches) | ability_bit(proto.ability_open_containers) | ability_bit(proto.ability_attack_players) | ability_bit(proto.ability_attack_mobs) | ability_bit(proto.ability_walk_speed)
	if flies {
		values |= ability_bit(proto.ability_may_fly) | ability_bit(proto.ability_instabuild)
	}
	all := (u32(1) << u32(proto.ability_count)) - 1
	return proto.SerializedLayer{
		serialized_layer:   proto.SerializedAbilitiesLayer.base
		abilities_set:      all
		ability_values:     values
		fly_speed:          0.05
		vertical_fly_speed: 0.05
		walk_speed:         0.1
	}
}

fn (s &NetworkSession) build_abilities() proto.SerializedAbilitiesData {
	flies := s.player.game_mode().allows_flying()
	is_op := s.player.perm.op()
	player_permission := if is_op {
		u8(proto.PlayerPermissionLevel.operator)
	} else {
		u8(proto.PlayerPermissionLevel.member)
	}
	command_permission := if is_op {
		proto.CommandPermissionLevel.admin
	} else {
		proto.CommandPermissionLevel.any
	}
	mut layers := proto.SerializedLayers{}
	layers << build_ability_layer(flies)
	return proto.SerializedAbilitiesData{
		target_player_raw_id: i64(s.runtime_id)
		player_permissions:   player_permission
		command_permissions:  command_permission
		layers:               layers
	}
}

// refresh_abilities may run from the session thread or the owning world
// thread, so it sends through the outbound queue.
fn (mut s NetworkSession) refresh_abilities() {
	s.deliver(&proto.UpdateAbilitiesPacket{
		data: s.build_abilities()
	})
}

fn adventure_settings() &proto.UpdateAdventureSettingsPacket {
	return &proto.UpdateAdventureSettingsPacket{
		adventure_settings: proto.AdventureSettings{
			show_name_tags: true
			auto_jump:      true
		}
	}
}
