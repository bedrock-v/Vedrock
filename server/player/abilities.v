module player

import bedrock_v.protocol.current as proto

pub fn ability_bit(index int) u32 {
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

// build_abilities is what the client is allowed to do, following from the
// player's game mode and whether they are an operator.
pub fn (p &Player) build_abilities() proto.SerializedAbilitiesData {
	flies := p.game_mode().allows_flying()
	is_op := p.perm.op()
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
	mut sink := p.sink
	return proto.SerializedAbilitiesData{
		target_player_raw_id: i64(sink.runtime_id())
		player_permissions:   player_permission
		command_permissions:  command_permission
		layers:               layers
	}
}

// refresh_abilities resends them after something that changes them such as a
// game mode change or an op grant.
pub fn (mut p Player) refresh_abilities() {
	mut sink := p.sink
	sink.deliver(&proto.UpdateAbilitiesPacket{
		data: p.build_abilities()
	})
}
