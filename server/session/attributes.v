module session

import bedrock_v.protocol.current as proto

fn (s &NetworkSession) health_update() &proto.UpdateAttributesPacket {
	return s.player.health_update()
}

fn (s &NetworkSession) update_attributes() &proto.UpdateAttributesPacket {
	return s.player.update_attributes()
}
