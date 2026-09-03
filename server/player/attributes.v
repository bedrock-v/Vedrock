module player

import bedrock_v.protocol.current as proto

// player_attribute builds one entry of an UpdateAttributesPacket. Bedrock
// wants the default bounds alongside the current ones on every send.
pub fn player_attribute(id string, min f32, max f32, current f32) proto.AttributeData {
	return proto.AttributeData{
		min_value:           min
		max_value:           max
		current_value:       current
		default_min:         min
		default_max:         max
		default_value:       current
		attribute_name:      id
		attribute_modifiers: []proto.AttributeModifier{}
	}
}

// health_update is the player's health alone, for the common case where
// nothing else changed.
pub fn (p &Player) health_update() &proto.UpdateAttributesPacket {
	mut sink := p.sink
	return &proto.UpdateAttributesPacket{
		target_runtime_id:       proto.actor_runtime_id(sink.runtime_id())
		attribute_list:          [
			player_attribute('minecraft:health', 0.0, 20.0, p.health()),
		]
		ticks_since_sim_started: 0
	}
}

// update_attributes is the player's full attribute set, sent once on spawn.
pub fn (p &Player) update_attributes() &proto.UpdateAttributesPacket {
	mut sink := p.sink
	experience := p.experience()
	return &proto.UpdateAttributesPacket{
		target_runtime_id:       proto.actor_runtime_id(sink.runtime_id())
		attribute_list:          [
			player_attribute('minecraft:health', 0.0, 20.0, p.health()),
			player_attribute('minecraft:movement', 0.0, 3.4028235e38, 0.1),
			player_attribute('minecraft:player.hunger', 0.0, 20.0, 20.0),
			player_attribute('minecraft:player.saturation', 0.0, 20.0, 20.0),
			player_attribute('minecraft:player.exhaustion', 0.0, 5.0, 0.0),
			player_attribute('minecraft:player.level', 0.0, max_experience_level,
				f32(experience.level)),
			player_attribute('minecraft:player.experience', 0.0, 1.0, experience.progress),
		]
		ticks_since_sim_started: 0
	}
}
