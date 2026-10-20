module session

import bedrock_v.protocol.current as proto
import bedrock_v.protocol.types
import server.player
import bedrock_v.protocol.version.v662.enums as enums_662
import bedrock_v.protocol.version.v924.enums as enums_924
import bedrock_v.protocol.version.v2168.packets as packets_2168
import bedrock_v.protocol.version.v662.packets as packets_662
import bedrock_v.protocol.version.v729.packets as packets_729
import bedrock_v.protocol.version.v776.packets as packets_776
import bedrock_v.protocol.version.v924.packets as packets_924
import bedrock_v.protocol.version.v2168.types as types_2168
import bedrock_v.protocol.version.v776.types as types_776
import bedrock_v.protocol.version.v944.types as types_944

// NetworkSession is the player.Sink for the player it drives: each method turns
// one thing the player needs told into the packets that tell them.
//
// It is the counterpart of viewer.v. A Viewer is shown what someone *else* did;
// a Sink is told about its own player which is why nothing here takes a
// &Player. The session already has one.

fn (mut s NetworkSession) show_message(message string) {
	s.deliver(&packets_924.TextPacket{
		message_type: enums_924.TextRaw{
			message: message
		}
	})
}

fn (mut s NetworkSession) show_translation(key string, parameters []string) {
	s.deliver(&packets_924.TextPacket{
		localize:     true
		message_type: enums_924.TextTranslate{
			message:        key
			parameter_list: parameters
		}
	})
}

fn (mut s NetworkSession) send_slot_update(slot int, wrapped types.ItemStackWrapper) {
	s.deliver(&packets_2168.InventorySlotPacket{
		container_id:        u32(player.inventory_window_id)
		slot:                u32(slot)
		container_name_data: types_944.FullContainerName{
			container: .inventory_container
		}
		item:                proto.item_descriptor_v2_tracked(wrapped.item_stack, wrapped.stack_id)
	})
}

fn (mut s NetworkSession) send_armor_slot_update(index int, wrapped types.ItemStackWrapper) {
	s.deliver(&packets_2168.InventorySlotPacket{
		container_id:        u32(player.armor_window_id)
		slot:                u32(index)
		container_name_data: types_944.FullContainerName{
			container: .armor_container
		}
		item:                proto.item_descriptor_v2_tracked(wrapped.item_stack, wrapped.stack_id)
	})
}

fn (mut s NetworkSession) send_inventory_cleared() {
	mut items := []types_2168.NetworkItemStackDescriptorV2{}
	for _ in 0 .. player.inventory_slot_count {
		items << proto.item_descriptor_v2(types.ItemStack{})
	}
	s.deliver(&packets_2168.InventoryContentPacket{
		inventory_id:        u32(player.inventory_window_id)
		slots:               items
		container_name_data: types_944.FullContainerName{
			container: .inventory_container
		}
		storage_item:        proto.item_descriptor_v2(types.ItemStack{})
	})
}

fn (mut s NetworkSession) send_game_mode(mode player.Gamemode) {
	s.deliver(&packets_662.SetPlayerGameTypePacket{
		player_game_type: proto.game_type(gamemode_to_wire(mode))
	})
}

fn (mut s NetworkSession) send_health() {
	s.deliver(s.health_update())
}

fn (mut s NetworkSession) send_experience() {
	if !s.spawned {
		return
	}
	s.deliver(s.experience_update())
}

fn (mut s NetworkSession) send_abilities() {
	s.deliver(&packets_776.UpdateAbilitiesPacket{
		data: s.build_abilities()
	})
}

fn player_attribute(id string, min f32, max f32, current f32) packets_729.AttributeData {
	return packets_729.AttributeData{
		min_value:           min
		max_value:           max
		current_value:       current
		default_min:         min
		default_max:         max
		default_value:       current
		attribute_name:      id
		attribute_modifiers: []packets_729.AttributeModifier{}
	}
}

// health_update is health alone for the common case where nothing else
// changed.
fn (s &NetworkSession) health_update() &packets_729.UpdateAttributesPacket {
	return &packets_729.UpdateAttributesPacket{
		target_runtime_id:       proto.actor_runtime_id(self_entity_runtime_id)
		attribute_list:          [
			player_attribute('minecraft:health', 0.0, 20.0, s.player.health()),
		]
		ticks_since_sim_started: 0
	}
}

fn (s &NetworkSession) hunger_update() &packets_729.UpdateAttributesPacket {
	state := s.player.hunger()
	return &packets_729.UpdateAttributesPacket{
		target_runtime_id:       proto.actor_runtime_id(self_entity_runtime_id)
		attribute_list:          [
			player_attribute('minecraft:player.hunger', 0.0, f32(player.max_food_level), f32(state.food_level)),
			player_attribute('minecraft:player.saturation', 0.0, f32(player.max_food_level), state.saturation),
			player_attribute('minecraft:player.exhaustion', 0.0, player.exhaustion_threshold, state.exhaustion),
		]
		ticks_since_sim_started: 0
	}
}

fn (s &NetworkSession) experience_update() &packets_729.UpdateAttributesPacket {
	state := s.player.experience()
	return &packets_729.UpdateAttributesPacket{
		target_runtime_id:       proto.actor_runtime_id(self_entity_runtime_id)
		attribute_list:          [
			player_attribute('minecraft:player.level', 0.0, player.max_experience_level, f32(state.level)),
			player_attribute('minecraft:player.experience', 0.0, 1.0, state.progress),
		]
		ticks_since_sim_started: 0
	}
}

// update_attributes is the full attribute set, sent once on spawn.
fn (s &NetworkSession) update_attributes() &packets_729.UpdateAttributesPacket {
	hunger := s.player.hunger()
	experience := s.player.experience()
	return &packets_729.UpdateAttributesPacket{
		target_runtime_id:       proto.actor_runtime_id(self_entity_runtime_id)
		attribute_list:          [
			player_attribute('minecraft:health', 0.0, 20.0, s.player.health()),
			player_attribute('minecraft:movement', 0.0, 3.4028235e38, 0.1),
			player_attribute('minecraft:player.hunger', 0.0, f32(player.max_food_level), f32(hunger.food_level)),
			player_attribute('minecraft:player.saturation', 0.0, f32(player.max_food_level), hunger.saturation),
			player_attribute('minecraft:player.exhaustion', 0.0, player.exhaustion_threshold, hunger.exhaustion),
			player_attribute('minecraft:player.level', 0.0, player.max_experience_level, f32(experience.level)),
			player_attribute('minecraft:player.experience', 0.0, 1.0, experience.progress),
		]
		ticks_since_sim_started: 0
	}
}

// The abilities below are what the client is allowed to do, following from the
// player's game mode and whether they are an operator.

pub fn ability_bit(index int) u32 {
	return u32(1) << u32(index)
}

fn build_ability_layer(flies bool) types_776.SerializedLayer {
	mut values := ability_bit(proto.ability_build) | ability_bit(proto.ability_mine) | ability_bit(proto.ability_doors_and_switches) | ability_bit(proto.ability_open_containers) | ability_bit(proto.ability_attack_players) | ability_bit(proto.ability_attack_mobs) | ability_bit(proto.ability_walk_speed)
	if flies {
		values |= ability_bit(proto.ability_may_fly) | ability_bit(proto.ability_instabuild)
	}
	all := (u32(1) << u32(proto.ability_count)) - 1
	return types_776.SerializedLayer{
		serialized_layer:   types_776.SerializedAbilitiesLayer.base
		abilities_set:      all
		ability_values:     values
		fly_speed:          0.05
		vertical_fly_speed: 0.05
		walk_speed:         0.1
	}
}

fn (mut s NetworkSession) build_abilities() types_776.SerializedAbilitiesData {
	return s.build_abilities_for(s.player)
}

// build_abilities_for is the same for a player this session is only watching
// where the id is this viewer's number for them rather than the self id.
fn (mut s NetworkSession) build_abilities_for(p &player.Player) types_776.SerializedAbilitiesData {
	flies := p.game_mode().allows_flying()
	is_op := p.perm.op()
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
	mut layers := []types_776.SerializedLayer{}
	layers << build_ability_layer(flies)
	return types_776.SerializedAbilitiesData{
		target_player_raw_id: i64(s.wire_id_for(p.runtime_id()))
		player_permissions:   player_permission
		command_permissions:  command_permission
		layers:               layers
	}
}

// gamemode_from_wire maps Bedrock's game type values onto player.Gamemode. The
// spectator variants all collapse: the server keeps one spectator mode.
fn gamemode_from_wire(v int) player.Gamemode {
	return match v {
		proto.game_type_creative {
			.creative
		}
		proto.game_type_adventure {
			.adventure
		}
		proto.game_type_spectator, proto.game_type_survival_spectator, proto.game_type_creative_spectator {
			.spectator
		}
		else {
			.survival
		}
	}
}

// gamemode_to_wire is the inverse of gamemode_from_wire.
fn gamemode_to_wire(g player.Gamemode) int {
	return match g {
		.survival { proto.game_type_survival }
		.creative { proto.game_type_creative }
		.adventure { proto.game_type_adventure }
		.spectator { proto.game_type_spectator }
	}
}
