module session

import protocol
import protocol.types
import server.item as itemmod

struct SlotChange {
	container types.FullContainerName
	info      protocol.StackResponseSlotInfo
}

const container_combined_hotbar_and_inventory = 12
const container_hotbar = 28
const container_inventory = 29

// flat_slot maps a window-0 container/slot pair onto the 0-35 player
// inventory layout (0-8 hotbar, 9-35 main grid). Other containers are
// not tracked and return none.
fn flat_slot(container types.FullContainerName, slot u8) ?int {
	return match container.container_id {
		container_hotbar, container_combined_hotbar_and_inventory { int(slot) }
		container_inventory { int(slot) + give_hotbar_size }
		else { none }
	}
}

fn (mut s NetworkSession) set_slot_stack(container types.FullContainerName, slot u8, net_id int) {
	flat := flat_slot(container, slot) or { return }
	if net_id == 0 {
		s.inv_slots.delete(flat)
	} else {
		s.inv_slots[flat] = net_id
	}
}

fn (s &NetworkSession) first_empty_slot() ?int {
	for slot in 0 .. inventory_slot_count {
		if slot !in s.inv_slots {
			return slot
		}
	}
	return none
}

fn (s &NetworkSession) inventory_stack_at(slot int) (types.ItemStack, int) {
	net := s.inv_slots[slot] or { return types.ItemStack{}, 0 }
	stack := s.inv_stacks[net] or { return types.ItemStack{}, 0 }
	return stack, net
}

fn (mut s NetworkSession) send_slot_update(slot int, wrapped types.ItemStackWrapper) {
	s.transport.send(&protocol.InventorySlotPacket{
		window_id:      inventory_window_id
		inventory_slot: slot
		container_name: ?types.FullContainerName(types.FullContainerName{
			container_id: 0
		})
		item:           wrapped
	}) or {}
}

fn (mut s NetworkSession) handle_mob_equipment(p protocol.MobEquipmentPacket) ! {
	// Reject an out-of-range hotbar slot before it feeds held_slot (used to
	// index the server inventory for combat damage).
	if p.hotbar_slot < 0 || p.hotbar_slot > 8 {
		return
	}
	s.held_item = p.item
	s.held_slot = p.hotbar_slot
	s.hub.broadcast_except(s.runtime_id, &protocol.MobEquipmentPacket{
		actor_runtime_id: s.runtime_id
		item:             p.item
		inventory_slot:   p.inventory_slot
		hotbar_slot:      p.hotbar_slot
		window_id:        p.window_id
	})
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
				protocol.stack_request_action_destroy {
					changes << s.apply_remove(action)
				}
				protocol.stack_request_action_drop {
					changes << s.apply_drop(action)
				}
				protocol.stack_request_action_consume {
					changes << s.apply_consume(action)
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
		count:            s.clamp_stack_count(item.numeric_id, 64)
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
	mut dest_stack := types.ItemStack{}
	if dst.stack_network_id != 0 {
		dest_stack = s.inv_stacks[dst.stack_network_id] or { types.ItemStack{} }
	}
	max_stack := s.max_stack_size_for_numeric(moved.id)
	if dest_stack.count > 0 && dest_stack.id == moved.id {
		space := max_stack - dest_stack.count
		if space <= 0 {
			return []SlotChange{}
		}
		if take > space {
			take = space
		}
	} else if take > max_stack {
		take = max_stack
	}
	if take == 0 {
		return []SlotChange{}
	}
	remaining := if from_creative { 0 } else { moved.count - take }

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
	s.set_slot_stack(dst.container, dst.slot, new_dest_id)
	s.set_slot_stack(src.container, src.slot, src_net)
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
	s.set_slot_stack(src.container, src.slot, new_src)
	s.set_slot_stack(dst.container, dst.slot, new_dst)
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
	s.set_slot_stack(src.container, src.slot, net)
	return [
		slot_change(src.container, src.slot, u8(remaining), net),
	]
}

fn (mut s NetworkSession) apply_drop(action protocol.StackRequestAction) []SlotChange {
	src := action.source
	item := s.inv_stacks[src.stack_network_id] or { types.ItemStack{} }
	mut take := int(action.count)
	if take == 0 || take > item.count {
		take = item.count
	}
	if take <= 0 {
		return []SlotChange{}
	}
	remaining := item.count - take
	s.inv_stacks.delete(src.stack_network_id)
	mut net := 0
	if remaining > 0 {
		mut st := item
		st.count = remaining
		net = s.track_stack(st)
	}
	s.set_slot_stack(src.container, src.slot, net)
	mut dropped := item
	dropped.count = take
	s.throw_item(dropped)
	return [
		slot_change(src.container, src.slot, u8(remaining), net),
	]
}

fn (mut s NetworkSession) apply_consume(action protocol.StackRequestAction) []SlotChange {
	src := action.source
	stack := s.inv_stacks[src.stack_network_id] or { return []SlotChange{} }
	name := s.hub.data.item_name(stack.id)
	result := s.hub.items.consume_result(name, stack.meta) or { return s.apply_remove(action) }
	for e in result.effects {
		s.apply_add_effect(e)
	}
	return s.replace_consumed_stack(action, stack, result)
}

fn (mut s NetworkSession) replace_consumed_stack(action protocol.StackRequestAction, stack types.ItemStack, result itemmod.ConsumeResult) []SlotChange {
	src := action.source
	mut take := int(action.count)
	if take == 0 || take > stack.count {
		take = stack.count
	}
	remaining := stack.count - take
	s.inv_stacks.delete(src.stack_network_id)

	mut net := 0
	mut count := remaining
	if remaining > 0 {
		mut remaining_stack := stack
		remaining_stack.count = remaining
		net = s.track_stack(remaining_stack)
	} else if result.replacement_id != '' && result.replacement_count > 0 {
		replacement_numeric_id := s.hub.data.item_id(result.replacement_id)
		if replacement_numeric_id != 0 || result.replacement_id == 'minecraft:air' {
			replacement := types.ItemStack{
				id:               replacement_numeric_id
				count:            result.replacement_count
				block_runtime_id: 0
				raw_extra_data:   []u8{}
			}
			net = s.track_stack(replacement)
			count = result.replacement_count
		}
	}

	s.set_slot_stack(src.container, src.slot, net)
	return [
		slot_change(src.container, src.slot, u8(count), net),
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
