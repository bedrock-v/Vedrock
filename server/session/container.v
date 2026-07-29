module session

import protocol.version.v662.enums as enums_662
import protocol.version.v685.packets as packets_685
import protocol.version.v898.packets as packets_898
import protocol.version.v944.packets as packets_944
import types
import server.internal.network

fn (mut s NetworkSession) handle_interact(p packets_898.InteractPacket) ! {
	if p.action != packets_898.InteractPacketAction.open_inventory {
		return
	}
	if s.inv_opened {
		return
	}
	s.inv_opened = true
	own := s.player.position()
	s.send_maybe_queued(&packets_944.ContainerOpenPacket{
		container_id:    enums_662.ContainerID.inventory
		container_type:  enums_662.ContainerType.inventory
		position:        network.block_pos_v944(types.BlockPosition{int(own.x), int(own.y), int(own.z)})
		target_actor_id: network.actor_unique_id(-1)
	})!
}

fn (mut s NetworkSession) handle_container_close(p packets_685.ContainerClosePacket) ! {
	s.inv_opened = false
	s.send_maybe_queued(&packets_685.ContainerClosePacket{
		container_id:           p.container_id
		container_type:         p.container_type
		server_initiated_close: false
	})!
}
