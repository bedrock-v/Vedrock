module session

import protocol.version.v944.packets as packets_944
import protocol.version.v944.enums as enums_944
import protocol.version.v944.types as types_944
import protocol.version.v766.types as types_766
import protocol.version.v975.packets as packets_975
import types
import server.item as itemmod
import server.internal.network

struct SlotChange {
	container types_944.FullContainerName
	info      types_766.ItemStackResponseSlotInfo
}

// flat_slot maps a window-0 container/slot pair onto the 0-35 player
// inventory layout (0-8 hotbar, 9-35 main grid). Other containers are
// not tracked and return none.
fn flat_slot(container types_944.FullContainerName, slot i8) ?int {
	return match container.container {
		.hotbar_container, .combined_hotbar_and_inventory_container { int(slot) }
		.inventory_container { int(slot) + give_hotbar_size }
		else { none }
	}
}

fn (mut s NetworkSession) set_slot_stack(container types_944.FullContainerName, slot i8, net_id int) {
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
	s.deliver(&packets_975.InventorySlotPacket{
		container_id:        u32(inventory_window_id)
		slot:                u32(slot)
		container_name_data: types_944.FullContainerName{
			container: .inventory_container
		}
		item:                network.item_descriptor_v975(wrapped.item_stack)
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

fn (t PlayerMobEquipmentTask) name() string {
	return 'PlayerMobEquipmentTask'
}

fn (t PlayerMobEquipmentTask) run(mut tx WorldTx) {
	mut target := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	target.player.set_held(t.hotbar_slot, t.item)
	tx.wr.broadcast_world_except(t.runtime_id, &packets_975.MobEquipmentPacket{
		target_runtime_id: network.actor_runtime_id(t.runtime_id)
		item:              network.item_descriptor_v975(t.item.item_stack)
		slot:              i8(t.inventory_slot)
		selected_slot:     i8(t.hotbar_slot)
		container_id:      .inventory
	})
}

fn (mut s NetworkSession) handle_mob_equipment(p packets_975.MobEquipmentPacket) ! {
	// Reject an out-of-range hotbar slot before it feeds held_slot (used to
	// index the server inventory for combat damage).
	hotbar_slot := int(p.selected_slot)
	if hotbar_slot < 0 || hotbar_slot > 8 {
		return
	}
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	if !wr.try_submit(PlayerMobEquipmentTask{
		runtime_id:     s.runtime_id
		epoch:          s.world_binding().epoch
		hotbar_slot:    hotbar_slot
		item:           types.ItemStackWrapper{
			item_stack: network.item_stack_from_descriptor_v975(p.item)
		}
		inventory_slot: int(p.slot)
		window_id:      int(p.container_id)
	}) {
		s.log.debug('Dropped mob equipment task - actor queue full')
	}
}

fn slot_change(container types_944.FullContainerName, slot i8, count int, net_id int) SlotChange {
	return SlotChange{
		container: container
		info:      types_766.ItemStackResponseSlotInfo{
			requested_slot:    slot
			slot:              slot
			amount:            i8(count)
			item_stack_net_id: i32(net_id)
		}
	}
}

fn stack_merge_compatible(a types.ItemStack, b types.ItemStack) bool {
	return a.id == b.id && a.meta == b.meta && a.block_runtime_id == b.block_runtime_id
		&& a.raw_extra_data == b.raw_extra_data
}

fn (mut s NetworkSession) handle_item_stack_request(p packets_944.ItemStackRequestPacket) ! {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	rid := s.runtime_id
	epoch := s.world_binding().epoch
	requests := p.requests
	responses := world_call[[]types_944.ItemStackResponseInfo](mut wr, fn [rid, epoch, requests] (mut tx WorldTx) []types_944.ItemStackResponseInfo {
		return process_item_stack_requests(mut tx, rid, epoch, requests)
	}) or { []types_944.ItemStackResponseInfo{} }
	s.send_maybe_queued(&packets_944.ItemStackResponsePacket{
		responses: responses
	})!
}

fn process_item_stack_requests(mut tx WorldTx, runtime_id u64, epoch i64, requests []packets_944.RequestsEntry) []types_944.ItemStackResponseInfo {
	mut target := tx.player_for_epoch(runtime_id, epoch) or {
		return []types_944.ItemStackResponseInfo{}
	}
	mut out := []types_944.ItemStackResponseInfo{}
	for request in requests {
		mut changes := []SlotChange{}
		for action in request.actions {
			match action {
				types_944.ItemStackActionTake {
					changes << target.apply_move(action.source, action.destination, action.amount)
				}
				types_944.ItemStackActionPlace {
					changes << target.apply_move(action.source, action.destination, action.amount)
				}
				types_944.ItemStackActionSwap {
					changes << target.apply_swap(action.source, action.destination)
				}
				types_944.ItemStackActionDestroy {
					changes << target.apply_remove(action.source, action.amount)
				}
				types_944.ItemStackActionDrop {
					changes << target.apply_drop(mut tx.wr, action.source, action.amount)
				}
				types_944.ItemStackActionConsume {
					changes << target.apply_consume(mut tx.wr, action.source, action.amount)
				}
				types_944.ItemStackActionCraftCreative {
					if target.player.game_mode() == network.game_type_creative {
						target.set_pending_creative(int(action.creative_item_network_id))
					} else {
						target.player.set_pending_creative(none)
					}
				}
				else {}
			}
		}
		out << types_944.ItemStackResponseInfo{
			result:            types_944.ItemStackNetResult{
				kind:               enums_944.ItemStackNetResultKind.success
				success_containers: group_changes(changes)
			}
			client_request_id: i32(request.client_request_id)
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

fn (mut s NetworkSession) apply_move(src types_944.ItemStackRequestSlotInfo, dst types_944.ItemStackRequestSlotInfo, amount i8) []SlotChange {
	mut moved := s.player.inv_stack(src.raw_id) or { types.ItemStack{} }
	mut from_creative := false
	if moved.count == 0 {
		if pending := s.player.pending_creative() {
			moved = pending
			from_creative = true
		}
	}
	mut take := int(amount)
	if take == 0 || take > moved.count {
		take = moved.count
	}
	mut dest_stack := types.ItemStack{}
	if dst.raw_id != 0 {
		dest_stack = s.player.inv_stack(dst.raw_id) or { types.ItemStack{} }
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

	s.player.delete_stack(src.raw_id)
	if dst.raw_id != 0 {
		s.player.delete_stack(dst.raw_id)
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
	s.set_slot_stack(dst.container_name, dst.slot, new_dest_id)
	s.set_slot_stack(src.container_name, src.slot, src_net)
	return [
		slot_change(dst.container_name, dst.slot, new_dest.count, new_dest_id),
		slot_change(src.container_name, src.slot, src_count, src_net),
	]
}

fn (mut s NetworkSession) apply_swap(src types_944.ItemStackRequestSlotInfo, dst types_944.ItemStackRequestSlotInfo) []SlotChange {
	a := s.player.inv_stack(src.raw_id) or { types.ItemStack{} }
	b := s.player.inv_stack(dst.raw_id) or { types.ItemStack{} }
	s.player.delete_stack(src.raw_id)
	s.player.delete_stack(dst.raw_id)
	mut new_src := 0
	if b.count > 0 {
		new_src = s.player.track_stack(b)
	}
	mut new_dst := 0
	if a.count > 0 {
		new_dst = s.player.track_stack(a)
	}
	s.set_slot_stack(src.container_name, src.slot, new_src)
	s.set_slot_stack(dst.container_name, dst.slot, new_dst)
	return [
		slot_change(src.container_name, src.slot, b.count, new_src),
		slot_change(dst.container_name, dst.slot, a.count, new_dst),
	]
}

fn (mut s NetworkSession) apply_remove(src types_944.ItemStackRequestSlotInfo, amount i8) []SlotChange {
	item := s.player.inv_stack(src.raw_id) or { types.ItemStack{} }
	mut take := int(amount)
	if take == 0 || take > item.count {
		take = item.count
	}
	remaining := item.count - take
	s.player.delete_stack(src.raw_id)
	mut net := 0
	if remaining > 0 {
		mut st := item
		st.count = remaining
		net = s.player.track_stack(st)
	}
	s.set_slot_stack(src.container_name, src.slot, net)
	return [
		slot_change(src.container_name, src.slot, remaining, net),
	]
}

fn (mut s NetworkSession) apply_drop(mut wr WorldRuntime, src types_944.ItemStackRequestSlotInfo, amount i8) []SlotChange {
	item := s.player.inv_stack(src.raw_id) or { types.ItemStack{} }
	mut take := int(amount)
	if take == 0 || take > item.count {
		take = item.count
	}
	changes := s.apply_remove(src, amount)
	if take > 0 && item.id != 0 {
		mut dropped := item
		dropped.count = take
		drop_player_item(mut wr, s, dropped)
	}
	return changes
}

// apply_consume receives the owning runtime explicitly so item effects are
// dispatched through the same world as the inventory request.
fn (mut s NetworkSession) apply_consume(mut wr WorldRuntime, src types_944.ItemStackRequestSlotInfo, amount i8) []SlotChange {
	stack := s.player.inv_stack(src.raw_id) or { return []SlotChange{} }
	name := s.hub.data.item_name(stack.id)
	result := s.hub.items.consume_result(name, stack.meta) or { return s.apply_remove(src, amount) }
	for e in result.effects {
		s.apply_add_effect(mut wr, e)
	}
	return s.replace_consumed_stack(src, amount, stack, result)
}

fn (mut s NetworkSession) replace_consumed_stack(src types_944.ItemStackRequestSlotInfo, amount i8, stack types.ItemStack, result itemmod.ConsumeResult) []SlotChange {
	mut take := int(amount)
	if take == 0 || take > stack.count {
		take = stack.count
	}
	remaining := stack.count - take
	s.player.delete_stack(src.raw_id)

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

	s.set_slot_stack(src.container_name, src.slot, net)
	return [
		slot_change(src.container_name, src.slot, count, net),
	]
}

fn group_changes(changes []SlotChange) []types_944.ItemStackResponseContainerInfo {
	mut infos := []types_944.ItemStackResponseContainerInfo{}
	for change in changes {
		mut found := false
		for mut info in infos {
			if info.container_name == change.container {
				info.slots << change.info
				found = true
				break
			}
		}
		if !found {
			infos << types_944.ItemStackResponseContainerInfo{
				container_name: change.container
				slots:          [change.info]
			}
		}
	}
	return infos
}
