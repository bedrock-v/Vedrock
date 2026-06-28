module session

import protocol

const ability_build = 0
const ability_mine = 1
const ability_doors_and_switches = 2
const ability_open_containers = 3
const ability_attack_players = 4
const ability_attack_mobs = 5
const ability_operator_commands = 6
const ability_teleport = 7
const ability_flying = 9
const ability_may_fly = 10
const ability_instabuild = 11
const ability_walk_speed = 14

const ability_count = 19

const ability_layer_base = u16(1)

fn ability_bit(index int) u32 {
	return u32(1) << u32(index)
}

fn build_ability_layer(creative bool) protocol.AbilitiesLayer {
	mut values := ability_bit(ability_build) | ability_bit(ability_mine) | ability_bit(ability_doors_and_switches) | ability_bit(ability_open_containers) | ability_bit(ability_attack_players) | ability_bit(ability_attack_mobs) | ability_bit(ability_walk_speed)
	if creative {
		values |= ability_bit(ability_may_fly) | ability_bit(ability_instabuild)
	}
	all := (u32(1) << u32(ability_count)) - 1
	return protocol.AbilitiesLayer{
		layer_id:           ability_layer_base
		set_abilities:      all
		set_ability_values: values
		fly_speed:          0.05
		vertical_fly_speed: 1.0
		walk_speed:         0.1
	}
}

fn (s &NetworkSession) build_abilities() protocol.AbilitiesData {
	creative := s.game_mode == 1 || s.game_mode == 6
	return protocol.AbilitiesData{
		target_actor_unique_id: i64(s.runtime_id)
		player_permission:      2
		command_permission:     0
		layers:                 [build_ability_layer(creative)]
	}
}
