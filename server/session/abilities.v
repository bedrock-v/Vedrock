module session

import protocol.version.v662.packets as packets_662
import protocol.version.v776.packets as packets_776
import protocol.version.v662.enums as enums_662
import protocol.version.v662.types as types_662
import protocol.version.v776.types as types_776
import server.internal.network

// Bedrock's UpdateAbilitiesPacket.command_permission wire values.
const command_permission_normal = u8(0)
const command_permission_operator = u8(1)

fn ability_bit(index int) u32 {
	return u32(1) << u32(index)
}

fn build_ability_layer(creative bool) types_662.SerializedLayer {
	mut values := ability_bit(network.ability_build) | ability_bit(network.ability_mine) | ability_bit(network.ability_doors_and_switches) | ability_bit(network.ability_open_containers) | ability_bit(network.ability_attack_players) | ability_bit(network.ability_attack_mobs) | ability_bit(network.ability_walk_speed)
	if creative {
		values |= ability_bit(network.ability_may_fly) | ability_bit(network.ability_instabuild)
	}
	all := (u32(1) << u32(network.ability_count)) - 1
	return types_662.SerializedLayer{
		serialized_layer: enums_662.SerializedAbilitiesLayer.base
		abilities_set:    all
		ability_values:   values
		fly_speed:        0.05
		walk_speed:       0.1
	}
}

fn build_ability_layer_776(creative bool) types_776.SerializedLayer {
	base := build_ability_layer(creative)
	return types_776.SerializedLayer{
		serialized_layer:   types_776.SerializedAbilitiesLayer.base
		abilities_set:      base.abilities_set
		ability_values:     base.ability_values
		fly_speed:          base.fly_speed
		vertical_fly_speed: base.fly_speed
		walk_speed:         base.walk_speed
	}
}

fn (s &NetworkSession) build_abilities() types_662.SerializedAbilitiesData {
	creative := s.player.game_mode() == network.game_type_creative
		|| s.player.game_mode() == network.game_type_spectator
	is_op := s.player.perm.op()
	player_permission := if is_op {
		enums_662.PlayerPermissionLevel.operator
	} else {
		enums_662.PlayerPermissionLevel.member
	}
	command_permission := if is_op {
		enums_662.CommandPermissionLevel.admin
	} else {
		enums_662.CommandPermissionLevel.any
	}
	return types_662.SerializedAbilitiesData{
		target_player_raw_id: i64(s.runtime_id)
		player_permissions:   player_permission
		command_permissions:  command_permission
		layers:               [build_ability_layer(creative)]
	}
}

fn (s &NetworkSession) build_abilities_776() types_776.SerializedAbilitiesData {
	creative := s.player.game_mode() == network.game_type_creative
		|| s.player.game_mode() == network.game_type_spectator
	is_op := s.player.perm.op()
	player_permission := if is_op {
		u8(enums_662.PlayerPermissionLevel.operator)
	} else {
		u8(enums_662.PlayerPermissionLevel.member)
	}
	command_permission := if is_op {
		enums_662.CommandPermissionLevel.admin
	} else {
		enums_662.CommandPermissionLevel.any
	}
	return types_776.SerializedAbilitiesData{
		target_player_raw_id: i64(s.runtime_id)
		player_permissions:   player_permission
		command_permissions:  command_permission
		layers:               [build_ability_layer_776(creative)]
	}
}

// refresh_abilities may run from the session thread or the owning world
// thread, so it sends through the outbound queue.
fn (mut s NetworkSession) refresh_abilities() {
	s.deliver(&packets_776.UpdateAbilitiesPacket{
		data: s.build_abilities_776()
	})
}

fn adventure_settings() &packets_662.UpdateAdventureSettingsPacket {
	return &packets_662.UpdateAdventureSettingsPacket{
		adventure_settings: types_662.AdventureSettings{
			show_name_tags: true
			auto_jump:      true
		}
	}
}
