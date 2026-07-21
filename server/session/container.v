module session

import protocol
import protocol.types

// window_type values for ContainerOpenPacket. The protocol module only defines
// container_type_inventory (0xff); the rest come from vanilla BDS.
const container_type_workbench = 1
const crafting_window_id = 1

fn (mut s NetworkSession) handle_interact(p protocol.InteractPacket) ! {
	if p.action != protocol.interact_action_open_inventory {
		return
	}
	if s.inv_opened {
		return
	}
	s.inv_opened = true
	s.transport.send(&protocol.ContainerOpenPacket{
		window_id:       0
		window_type:     protocol.container_type_inventory
		block_position:  types.BlockPosition{int(s.position.x), int(s.position.y), int(s.position.z)}
		actor_unique_id: -1
	})!
}

// open_crafting_container sends a ContainerOpenPacket for the workbench
// (3x3 crafting grid) at the given block position.
fn (mut s NetworkSession) open_crafting_container(pos types.BlockPosition) ! {
	if s.inv_opened {
		return
	}
	s.inv_opened = true
	s.transport.send(&protocol.ContainerOpenPacket{
		window_id:       crafting_window_id
		window_type:     container_type_workbench
		block_position:  pos
		actor_unique_id: -1
	})!
}

fn (mut s NetworkSession) handle_container_close(p protocol.ContainerClosePacket) ! {
	s.inv_opened = false
	s.transport.send(&protocol.ContainerClosePacket{
		window_id:   p.window_id
		window_type: p.window_type
		server:      false
	})!
}
