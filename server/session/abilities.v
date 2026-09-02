module session

import bedrock_v.protocol.current as proto

// Bedrock's UpdateAbilitiesPacket.command_permission wire values.
const command_permission_normal = u8(0)
const command_permission_operator = u8(1)

fn (s &NetworkSession) build_abilities() proto.SerializedAbilitiesData {
	return s.player.build_abilities()
}

fn (mut s NetworkSession) refresh_abilities() {
	s.player.refresh_abilities()
}

fn adventure_settings() &proto.UpdateAdventureSettingsPacket {
	return &proto.UpdateAdventureSettingsPacket{
		adventure_settings: proto.AdventureSettings{
			show_name_tags: true
			auto_jump:      true
		}
	}
}
