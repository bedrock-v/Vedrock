module session

import protocol

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
	return protocol.AbilitiesData{
		target_actor_unique_id: i64(s.runtime_id)
		player_permission:      2
		command_permission:     0
		layers:                 [build_ability_layer(creative)]
	}
}

fn adventure_settings() &protocol.UpdateAdventureSettingsPacket {
	return &protocol.UpdateAdventureSettingsPacket{
		show_name_tags: true
		auto_jump:      true
	}
}
