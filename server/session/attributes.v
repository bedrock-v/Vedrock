module session

import protocol.version.v729.packets as packets_729
import server.internal.network

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

fn (s &NetworkSession) health_update() &packets_729.UpdateAttributesPacket {
	return &packets_729.UpdateAttributesPacket{
		target_runtime_id:       network.actor_runtime_id(s.runtime_id)
		attribute_list:          [
			player_attribute('minecraft:health', 0.0, 20.0, s.player.health()),
		]
		ticks_since_sim_started: 0
	}
}

fn (s &NetworkSession) update_attributes() &packets_729.UpdateAttributesPacket {
	return &packets_729.UpdateAttributesPacket{
		target_runtime_id:       network.actor_runtime_id(s.runtime_id)
		attribute_list:          [
			player_attribute('minecraft:health', 0.0, 20.0, s.player.health()),
			player_attribute('minecraft:movement', 0.0, 3.4028235e38, 0.1),
			player_attribute('minecraft:player.hunger', 0.0, 20.0, 20.0),
			player_attribute('minecraft:player.saturation', 0.0, 20.0, 20.0),
			player_attribute('minecraft:player.exhaustion', 0.0, 5.0, 0.0),
			player_attribute('minecraft:player.level', 0.0, 24791.0, 0.0),
			player_attribute('minecraft:player.experience', 0.0, 1.0, 0.0),
		]
		ticks_since_sim_started: 0
	}
}
