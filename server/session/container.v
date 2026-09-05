module session

import bedrock_v.protocol.types
import bedrock_v.protocol.current as proto
import server.entity
import server.worldrt

fn (mut s NetworkSession) handle_interact(p proto.InteractPacket) ! {
	if p.action != proto.InteractPacketAction.open_inventory {
		return
	}
	if s.inv_opened {
		return
	}

	if s.workbench_open() || s.open_container_position() != none {
		s.log.debug('handle_interact: ignored open_inventory - workbench_open=${s.workbench_open()} chest_open=${s.open_container_position() != none}')
		return
	}
	s.inv_opened = true
	own := s.player.position()
	s.log.debug('handle_interact: opening plain inventory screen')
	s.send_maybe_queued(&proto.ContainerOpenPacket{
		container_id:    proto.ContainerID.inventory
		container_type:  proto.ContainerType.inventory
		position:        proto.block_pos(types.BlockPosition{int(own.x), int(own.y), int(own.z)})
		target_actor_id: proto.actor_unique_id(-1)
	})!
}

fn (mut s NetworkSession) handle_container_close(p proto.ContainerClosePacket) ! {
	s.log.debug('handle_container_close: container_id=${p.container_id} workbench_open=${s.workbench_open()} chest_open=${s.open_container_position() != none}')
	if p.container_id == proto.ContainerID.inventory {
		s.inv_opened = false
	} else if int(p.container_id) == chest_dynamic_container_id() {
		if s.workbench_open() {
			s.release_workbench()
		} else {
			s.release_open_chest_container()
		}
	}
	s.send_maybe_queued(&proto.ContainerClosePacket{
		container_id:           p.container_id
		container_type:         p.container_type
		server_initiated_close: false
	})!
}

// release_open_chest_container runs close_chest_container on the owning
// world's actor.
fn (mut s NetworkSession) release_open_chest_container() {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	id := s.actor_id()
	wr.submit(CloseChestContainerTask{
		id: id
	})
}

struct CloseChestContainerTask {
	id entity.ActorId
}

fn (t CloseChestContainerTask) name() string {
	return 'CloseChestContainerTask'
}

fn (t CloseChestContainerTask) run(mut tx worldrt.WorldTx) {
	mut target := player_for_id(mut tx, t.id) or { return }
	target.close_chest_container(mut tx)
}
