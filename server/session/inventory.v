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
		s.player.delete_slot(flat)
	} else {
		s.player.set_slot(flat, net_id)
	}
}

fn (s &NetworkSession) first_empty_slot() ?int {
	for slot in 0 .. inventory_slot_count {
		if !s.player.has_slot(slot) {
			return slot
		}
	}
	return none
}

fn (s &NetworkSession) inventory_stack_at(slot int) (types.ItemStack, int) {
	net := s.player.inv_slot(slot) or { return types.ItemStack{}, 0 }
	stack := s.player.inv_stack(net) or { return types.ItemStack{}, 0 }
	return stack, net
}

// send_slot_update keeps the client's inventory view in sync after slot
// changes, including mutations performed by world owned gameplay tasks.
fn (mut s NetworkSession) send_slot_update(slot int, wrapped types.ItemStackWrapper) {
	s.deliver(&protocol.InventorySlotPacket{
		window_id:      inventory_window_id
		inventory_slot: slot
		container_name: ?types.FullContainerName(types.FullContainerName{
			container_id: 0
		})
		item:           wrapped
	})
}

// PlayerMobEquipmentTask applies held slot changes on the owning world
// runtime, so the equipment packet other players see is scoped to that
// world.
struct PlayerMobEquipmentTask {
	runtime_id     u64
	epoch          i64
	hotbar_slot    int
	item           types.ItemStackWrapper
	inventory_slot int
	window_id      int
}

fn (t PlayerMobEquipmentTask) run(mut tx WorldTx) {
	mut target := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	target.player.set_held(t.hotbar_slot, t.item)
	tx.wr.broadcast_world_except(t.runtime_id, &protocol.MobEquipmentPacket{
		actor_runtime_id: t.runtime_id
		item:             t.item
		inventory_slot:   t.inventory_slot
		hotbar_slot:      t.hotbar_slot
		window_id:        t.window_id
	})
}

fn (mut s NetworkSession) handle_mob_equipment(p protocol.MobEquipmentPacket) ! {
	// Reject an out-of-range hotbar slot before it feeds held_slot (used to
	// index the server inventory for combat damage).
	if p.hotbar_slot < 0 || p.hotbar_slot > 8 {
		return
	}
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	if !wr.try_submit(PlayerMobEquipmentTask{
		runtime_id:     s.runtime_id
		epoch:          s.world_binding().epoch
		hotbar_slot:    p.hotbar_slot
		item:           p.item
		inventory_slot: p.inventory_slot
		window_id:      p.window_id
	}) {
		s.log.debug('Dropped mob equipment task - actor queue full')
	}
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

fn stack_merge_compatible(a types.ItemStack, b types.ItemStack) bool {
	return a.id == b.id && a.meta == b.meta && a.block_runtime_id == b.block_runtime_id
		&& a.raw_extra_data == b.raw_extra_data
}

fn (mut s NetworkSession) handle_item_stack_request(p protocol.ItemStackRequestPacket) ! {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	rid := s.runtime_id
	epoch := s.world_binding().epoch
	requests := p.requests
	responses := world_call[[]protocol.ItemStackResponseEntry](mut wr, fn [rid, epoch, requests] (mut tx WorldTx) []protocol.ItemStackResponseEntry {
		return process_item_stack_requests(mut tx, rid, epoch, requests)
	}) or { []protocol.ItemStackResponseEntry{} }
	s.send_maybe_queued(&protocol.ItemStackResponsePacket{
		responses: responses
	})!
}

fn process_item_stack_requests(mut tx WorldTx, runtime_id u64, epoch i64, requests []protocol.ItemStackRequestEntry) []protocol.ItemStackResponseEntry {
	mut target := tx.player_for_epoch(runtime_id, epoch) or {
		return []protocol.ItemStackResponseEntry{}
	}
	mut out := []protocol.ItemStackResponseEntry{}
	for request in requests {
		mut changes := []SlotChange{}
		for action in request.actions {
			match action.action_type {
				protocol.stack_request_action_take, protocol.stack_request_action_place,
				protocol.stack_request_action_place_in_container,
				protocol.stack_request_action_take_out_container {
					changes << target.apply_move(action)
				}
				protocol.stack_request_action_swap {
					changes << target.apply_swap(action)
				}
				protocol.stack_request_action_destroy, protocol.stack_request_action_drop {
					changes << target.apply_remove(action)
				}
				protocol.stack_request_action_consume {
					changes << target.apply_consume(mut tx.wr, action)
				}
				protocol.stack_request_action_craft_creative {
					if target.player.game_mode() == protocol.game_type_creative {
						target.set_pending_creative(int(action.creative_item_network_id))
					} else {
						target.player.set_pending_creative(none)
					}
				}
				else {}
			}
		}
		out << protocol.ItemStackResponseEntry{
			status:         protocol.item_stack_response_status_ok
			request_id:     request.request_id
			container_info: group_changes(changes)
		}
	}
	return out
}

fn (mut s NetworkSession) set_pending_creative(entry_id int) {
	creative := s.hub.data.creative_items
	index := entry_id - 1
	if index < 0 || index >= creative.len {
		s.player.set_pending_creative(none)
		return
	}
	item := creative[index]
	s.player.set_pending_creative(types.ItemStack{
		id:               item.numeric_id
		meta:             item.meta
		count:            s.clamp_stack_count(item.numeric_id, 64)
		block_runtime_id: item.block_runtime_id
		raw_extra_data:   []u8{}
	})
}

fn (mut s NetworkSession) apply_move(action protocol.StackRequestAction) []SlotChange {
	src := action.source
	dst := action.destination
	mut moved := s.player.inv_stack(src.stack_network_id) or { types.ItemStack{} }
	mut from_creative := false
	if moved.count == 0 {
		if pending := s.player.pending_creative() {
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
		dest_stack = s.player.inv_stack(dst.stack_network_id) or { types.ItemStack{} }
	}
	max_stack := s.max_stack_size_for_numeric(moved.id)
	can_merge := dest_stack.count > 0 && stack_merge_compatible(moved, dest_stack)
	if dest_stack.count > 0 && !can_merge {
		return []SlotChange{}
	}
	if can_merge {
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
	if can_merge {
		new_dest.count = dest_stack.count + take
	} else {
		new_dest.count = take
	}

	s.player.delete_stack(src.stack_network_id)
	if dst.stack_network_id != 0 {
		s.player.delete_stack(dst.stack_network_id)
	}
	new_dest_id := s.player.track_stack(new_dest)

	if from_creative {
		s.player.set_pending_creative(none)
	}

	mut src_net := 0
	mut src_count := 0
	if remaining > 0 {
		mut src_stack := moved
		src_stack.count = remaining
		src_net = s.player.track_stack(src_stack)
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
	a := s.player.inv_stack(src.stack_network_id) or { types.ItemStack{} }
	b := s.player.inv_stack(dst.stack_network_id) or { types.ItemStack{} }
	s.player.delete_stack(src.stack_network_id)
	s.player.delete_stack(dst.stack_network_id)
	mut new_src := 0
	if b.count > 0 {
		new_src = s.player.track_stack(b)
	}
	mut new_dst := 0
	if a.count > 0 {
		new_dst = s.player.track_stack(a)
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
	item := s.player.inv_stack(src.stack_network_id) or { types.ItemStack{} }
	mut take := int(action.count)
	if take == 0 || take > item.count {
		take = item.count
	}
	remaining := item.count - take
	s.player.delete_stack(src.stack_network_id)
	mut net := 0
	if remaining > 0 {
		mut st := item
		st.count = remaining
		net = s.player.track_stack(st)
	}
	s.set_slot_stack(src.container, src.slot, net)
	return [
		slot_change(src.container, src.slot, u8(remaining), net),
	]
}

// apply_consume receives the owning runtime explicitly so item effects are
// dispatched through the same world as the inventory request.
fn (mut s NetworkSession) apply_consume(mut wr WorldRuntime, action protocol.StackRequestAction) []SlotChange {
	src := action.source
	stack := s.player.inv_stack(src.stack_network_id) or { return []SlotChange{} }
	name := s.hub.data.item_name(stack.id)
	result := s.hub.items.consume_result(name, stack.meta) or { return s.apply_remove(action) }
	for e in result.effects {
		s.apply_add_effect(mut wr, e)
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
	s.player.delete_stack(src.stack_network_id)

	mut net := 0
	mut count := remaining
	if remaining > 0 {
		mut remaining_stack := stack
		remaining_stack.count = remaining
		net = s.player.track_stack(remaining_stack)
	} else if result.replacement_id != '' && result.replacement_count > 0 {
		replacement_numeric_id := s.hub.data.item_id(result.replacement_id)
		if replacement_numeric_id != 0 || result.replacement_id == 'minecraft:air' {
			replacement := types.ItemStack{
				id:               replacement_numeric_id
				count:            result.replacement_count
				block_runtime_id: 0
				raw_extra_data:   []u8{}
			}
			net = s.player.track_stack(replacement)
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
