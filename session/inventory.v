module session

import protocol
import protocol.types

struct SlotChange {
	container types.FullContainerName
	info      protocol.StackResponseSlotInfo
}

fn (mut s NetworkSession) track_stack(stack types.ItemStack) int {
	id := s.inv_next_id
	s.inv_next_id++
	s.inv_stacks[id] = stack
	return id
}

fn slot_change(container types.FullContainerName, slot u8, count u8, net_id int) SlotChange {
	return SlotChange{
		container: container
		info:      protocol.StackResponseSlotInfo{
			slot:             slot
			hotbar_slot:      slot
			count:            count
			stack_network_id: net_id
		}
	}
}

fn (mut s NetworkSession) handle_item_stack_request(p protocol.ItemStackRequestPacket) ! {
	mut responses := []protocol.ItemStackResponseEntry{}
	for request in p.requests {
		mut changes := []SlotChange{}
		for action in request.actions {
			match action.action_type {
				protocol.stack_request_action_take, protocol.stack_request_action_place,
				protocol.stack_request_action_place_in_container,
				protocol.stack_request_action_take_out_container {
					changes << s.apply_move(action)
				}
				protocol.stack_request_action_swap {
					changes << s.apply_swap(action)
				}
				protocol.stack_request_action_destroy, protocol.stack_request_action_drop,
				protocol.stack_request_action_consume {
					changes << s.apply_remove(action)
				}
				protocol.stack_request_action_craft_creative {
					s.set_pending_creative(int(action.creative_item_network_id))
				}
				else {}
			}
		}
		responses << protocol.ItemStackResponseEntry{
			status:         protocol.item_stack_response_status_ok
			request_id:     request.request_id
			container_info: group_changes(changes)
		}
	}
	s.transport.send(&protocol.ItemStackResponsePacket{
		responses: responses
	})!
}

fn (mut s NetworkSession) set_pending_creative(entry_id int) {
	creative := s.hub.data.creative_items
	index := entry_id - 1
	if index < 0 || index >= creative.len {
		s.pending_creative = none
		return
	}
	item := creative[index]
	s.pending_creative = types.ItemStack{
		id:               item.numeric_id
		meta:             item.meta
		count:            64
		block_runtime_id: item.block_runtime_id
		raw_extra_data:   []u8{}
	}
}

fn (mut s NetworkSession) apply_move(action protocol.StackRequestAction) []SlotChange {
	src := action.source
	dst := action.destination
	mut moved := s.inv_stacks[src.stack_network_id] or { types.ItemStack{} }
	mut from_creative := false
	if moved.count == 0 {
		if pending := s.pending_creative {
			moved = pending
			from_creative = true
		}
	}
	mut take := int(action.count)
	if take == 0 || take > moved.count {
		take = moved.count
	}
	if take == 0 {
		return []SlotChange{}
	}
	remaining := if from_creative { 0 } else { moved.count - take }

	mut dest_stack := types.ItemStack{}
	if dst.stack_network_id != 0 {
		dest_stack = s.inv_stacks[dst.stack_network_id] or { types.ItemStack{} }
	}
	mut new_dest := moved
	if dest_stack.count > 0 && dest_stack.id == moved.id {
		new_dest.count = dest_stack.count + take
	} else {
		new_dest.count = take
	}

	s.inv_stacks.delete(src.stack_network_id)
	if dst.stack_network_id != 0 {
		s.inv_stacks.delete(dst.stack_network_id)
	}
	new_dest_id := s.track_stack(new_dest)

	if from_creative {
		s.pending_creative = none
	}

	mut src_net := 0
	mut src_count := 0
	if remaining > 0 {
		mut src_stack := moved
		src_stack.count = remaining
		src_net = s.track_stack(src_stack)
		src_count = remaining
	}
	return [
		slot_change(dst.container, dst.slot, u8(new_dest.count), new_dest_id),
		slot_change(src.container, src.slot, u8(src_count), src_net),
	]
}

fn (mut s NetworkSession) apply_swap(action protocol.StackRequestAction) []SlotChange {
	src := action.source
	dst := action.destination
	a := s.inv_stacks[src.stack_network_id] or { types.ItemStack{} }
	b := s.inv_stacks[dst.stack_network_id] or { types.ItemStack{} }
	s.inv_stacks.delete(src.stack_network_id)
	s.inv_stacks.delete(dst.stack_network_id)
	mut new_src := 0
	if b.count > 0 {
		new_src = s.track_stack(b)
	}
	mut new_dst := 0
	if a.count > 0 {
		new_dst = s.track_stack(a)
	}
	return [
		slot_change(src.container, src.slot, u8(b.count), new_src),
		slot_change(dst.container, dst.slot, u8(a.count), new_dst),
	]
}

fn (mut s NetworkSession) apply_remove(action protocol.StackRequestAction) []SlotChange {
	src := action.source
	item := s.inv_stacks[src.stack_network_id] or { types.ItemStack{} }
	mut take := int(action.count)
	if take == 0 || take > item.count {
		take = item.count
	}
	remaining := item.count - take
	s.inv_stacks.delete(src.stack_network_id)
	mut net := 0
	if remaining > 0 {
		mut st := item
		st.count = remaining
		net = s.track_stack(st)
	}
	return [
		slot_change(src.container, src.slot, u8(remaining), net),
	]
}

fn group_changes(changes []SlotChange) []protocol.StackResponseContainerInfo {
	mut infos := []protocol.StackResponseContainerInfo{}
	for change in changes {
		mut found := false
		for mut info in infos {
			if info.container.container_id == change.container.container_id {
				info.slot_info << change.info
				found = true
				break
			}
		}
		if !found {
			infos << protocol.StackResponseContainerInfo{
				container: change.container
				slot_info: [change.info]
			}
		}
	}
	return infos
}
