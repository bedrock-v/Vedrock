module session

import protocol
import protocol.types

fn player_attribute(id string, min f32, max f32, current f32) types.UpdateAttribute {
	return types.UpdateAttribute{
		id:          id
		min:         min
		max:         max
		current:     current
		default_min: min
		default_max: max
		default:     current
		modifiers:   []types.AttributeModifier{}
	}
}

fn (s &NetworkSession) health_update() &protocol.UpdateAttributesPacket {
	return &protocol.UpdateAttributesPacket{
		actor_runtime_id: s.runtime_id
		entries:          [
			player_attribute('minecraft:health', 0.0, 20.0, s.player.health()),
		]
		tick:             0
	}
}

fn (s &NetworkSession) update_attributes() &protocol.UpdateAttributesPacket {
	return &protocol.UpdateAttributesPacket{
		actor_runtime_id: s.runtime_id
		entries:          [
			player_attribute('minecraft:health', 0.0, 20.0, s.player.health()),
			player_attribute('minecraft:movement', 0.0, 3.4028235e38, 0.1),
			player_attribute('minecraft:player.hunger', 0.0, 20.0, 20.0),
			player_attribute('minecraft:player.saturation', 0.0, 20.0, 20.0),
			player_attribute('minecraft:player.exhaustion', 0.0, 5.0, 0.0),
			player_attribute('minecraft:player.level', 0.0, 24791.0, 0.0),
			player_attribute('minecraft:player.experience', 0.0, 1.0, 0.0),
		]
		tick:             0
	}
}
