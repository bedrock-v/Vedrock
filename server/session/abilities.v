module session

import protocol

// Bedrock's UpdateAbilitiesPacket.command_permission wire values.
const command_permission_normal = u8(0)
const command_permission_operator = u8(1)

fn ability_bit(index int) u32 {
	return u32(1) << u32(index)
}

fn build_ability_layer(creative bool) protocol.AbilitiesLayer {
	mut values := ability_bit(protocol.ability_build) | ability_bit(protocol.ability_mine) | ability_bit(protocol.ability_doors_and_switches) | ability_bit(protocol.ability_open_containers) | ability_bit(protocol.ability_attack_players) | ability_bit(protocol.ability_attack_mobs) | ability_bit(protocol.ability_walk_speed)
	if creative {
		values |= ability_bit(protocol.ability_may_fly) | ability_bit(protocol.ability_instabuild)
	}
	all := (u32(1) << u32(protocol.ability_count)) - 1
	return protocol.AbilitiesLayer{
		layer_id:           protocol.ability_layer_base
		set_abilities:      all
		set_ability_values: values
		fly_speed:          0.05
		vertical_fly_speed: 1.0
		walk_speed:         0.1
	}
}

fn (s &NetworkSession) build_abilities() protocol.AbilitiesData {
	creative := s.game_mode == protocol.game_type_creative
		|| s.game_mode == protocol.game_type_spectator
	is_op := s.perm.op()
	player_permission := if is_op {
		protocol.permission_level_operator
	} else {
		protocol.permission_level_member
	}
	command_permission := if is_op { command_permission_operator } else { command_permission_normal }
	return protocol.AbilitiesData{
		target_actor_unique_id: i64(s.runtime_id)
		player_permission:      u8(player_permission)
		command_permission:     command_permission
		layers:                 [build_ability_layer(creative)]
	}
}

pub fn (mut s NetworkSession) refresh_abilities() {
	s.transport.send(&protocol.UpdateAbilitiesPacket{
		data: s.build_abilities()
	}) or {}
}

fn adventure_settings() &protocol.UpdateAdventureSettingsPacket {
	return &protocol.UpdateAdventureSettingsPacket{
		show_name_tags: true
		auto_jump:      true
	}
}
