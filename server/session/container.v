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
	// Send empty contents so the client initializes the crafting grid.
	empty_wrapper := types.item_stack_wrapper_legacy(types.ItemStack{})
	mut empty9 := []types.ItemStackWrapper{len: 9}
	for i in 0 .. 9 {
		empty9[i] = empty_wrapper
	}
	s.transport.send(&protocol.InventoryContentPacket{
		window_id:      crafting_window_id
		items:          empty9
		container_name: types.FullContainerName{container_id: container_crafting_input}
		storage:        empty_wrapper
	})!
	s.transport.send(&protocol.InventoryContentPacket{
		window_id:      crafting_window_id
		items:          [empty_wrapper]
		container_name: types.FullContainerName{container_id: container_crafting_output}
		storage:        empty_wrapper
	})!
}

fn (mut s NetworkSession) handle_container_close(p protocol.ContainerClosePacket) ! {
	s.inv_opened = false
	s.transport.send(&protocol.ContainerClosePacket{
		window_id:   p.window_id
		window_type: p.window_type
		server:      false
	})!
	if p.window_id == crafting_window_id {
		s.return_crafting_items()
		// Send full inventory content so the client refreshes its view.
		mut items := []types.ItemStackWrapper{}
		for i in 0 .. inventory_slot_count {
			if net_id := s.inv_slots[i] {
				stack := s.inv_stacks[net_id] or {
					items << types.item_stack_wrapper_legacy(types.ItemStack{})
					continue
				}
				items << wrap_stack_id(stack, net_id)
			} else {
				items << types.item_stack_wrapper_legacy(types.ItemStack{})
			}
		}
		s.transport.send(&protocol.InventoryContentPacket{
			window_id:      0
			items:          items
			container_name: types.FullContainerName{container_id: 0}
			storage:        types.item_stack_wrapper_legacy(types.ItemStack{})
		}) or {}
	}
}
