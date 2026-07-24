module session

import protocol
import protocol.types

fn (mut s NetworkSession) handle_interact(p protocol.InteractPacket) ! {
	if p.action != protocol.interact_action_open_inventory {
		return
	}
	if s.inv_opened {
		return
	}
	s.inv_opened = true
	own := s.player.position()
	s.send_maybe_queued(&protocol.ContainerOpenPacket{
		window_id:       0
		window_type:     protocol.container_type_inventory
		block_position:  types.BlockPosition{int(own.x), int(own.y), int(own.z)}
		actor_unique_id: -1
	})!
}

fn (mut s NetworkSession) handle_container_close(p protocol.ContainerClosePacket) ! {
	s.inv_opened = false
	s.send_maybe_queued(&protocol.ContainerClosePacket{
		window_id:   p.window_id
		window_type: p.window_type
		server:      false
	})!
}
