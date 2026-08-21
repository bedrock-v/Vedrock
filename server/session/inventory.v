module session

import protocol.types
import server.item as itemmod
import protocol.current as proto

struct SlotChange {
	container proto.FullContainerName
	info      proto.ItemStackResponseSlotInfo
}

// flat_slot maps supported window-0 container slots directly onto the
// player's flat 0-35 inventory. Hotbar, inventory and combined containers
// all use the same slot numbering so no offset is applied.
//
// Unsupported containers return none.
fn flat_slot(container proto.FullContainerName, slot i8) ?int {
	return match container.container {
		.hotbar_container, .combined_hotbar_and_inventory_container, .inventory_container { int(slot) }
		else { none }
	}
}

// persist_container_changes saves changes to slots in the target's open
// container and updates their network IDs to match the resulting stacks.
//
// SlotChange already contains everything needed, so inventory operations
// remain independent of container types.
fn persist_container_changes(mut tx WorldTx, mut target NetworkSession, changes []SlotChange) {
	pos := target.open_container_position() or { return }
	for change in changes {
		if change.container.container != .dynamic_container {
			continue
		}
		if change.container.dynamic_id or { -1 } != i32(chest_dynamic_container_id) {
			continue
		}
		slot := int(change.info.slot)
		net_id := int(change.info.item_stack_net_id or { 0 })
		stack := if net_id != 0 {
			target.player.inv_stack(net_id) or { types.ItemStack{} }
		} else {
			types.ItemStack{}
		}
		tx.wr.world.set_container_slot(pos.x, pos.y, pos.z, slot, stack)
		target.set_open_container_slot_net_id(slot, net_id)
	}
}

fn (mut s NetworkSession) set_slot_stack(container proto.FullContainerName, slot i8, net_id int) {
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

// resolve_request_stack finds the item an ItemStackRequestSlotInfo refers
// to, server side, via container & slot address. The client's declared
// raw_id is a fallback only, never the primary lookup key: a slot the
// server hasn't given the client a net id for (see
// item_descriptor_v2_tracked) has no id the client could have declared
// correctly, so trusting raw_id first would drop the request.
fn (s &NetworkSession) resolve_request_stack(container proto.FullContainerName, slot i8, raw_id int) (types.ItemStack, int) {
	if flat := flat_slot(container, slot) {
		return s.inventory_stack_at(flat)
	}
	if container.container == .dynamic_container
		&& container.dynamic_id or { -1 } == i32(chest_dynamic_container_id)
		&& s.open_container_position() != none {
		net_id := s.open_container_slot_net_id(int(slot))
		if net_id == 0 {
			return types.ItemStack{}, 0
		}
		if stack := s.player.inv_stack(net_id) {
			return stack, net_id
		}
		return types.ItemStack{}, 0
	}
	if raw_id != 0 {
		if stack := s.player.inv_stack(raw_id) {
			return stack, raw_id
		}
	}
	return types.ItemStack{}, 0
}

// send_slot_update keeps the client's inventory view in sync after slot
// changes, including mutations performed by world owned gameplay tasks.
// wrapped.stack_id must reach the wire via item_descriptor_v2_tracked,
// not the bare item_descriptor_v2. A descriptor with no net id teaches
// the client nothing about this slot's id.
fn (mut s NetworkSession) send_slot_update(slot int, wrapped types.ItemStackWrapper) {
	s.deliver(&proto.InventorySlotPacket{
		container_id:        u32(inventory_window_id)
		slot:                u32(slot)
		container_name_data: proto.FullContainerName{
			container: .inventory_container
		}
		item:                proto.item_descriptor_v2_tracked(wrapped.item_stack,
			wrapped.stack_id)
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
	tx.wr.broadcast_world_except(t.runtime_id, &proto.MobEquipmentPacket{
		target_runtime_id: proto.actor_runtime_id(t.runtime_id)
		item:              proto.item_descriptor_v2(t.item.item_stack)
		slot:              i8(t.inventory_slot)
		selected_slot:     i8(t.hotbar_slot)
		container_id:      .inventory
	})
}

fn (mut s NetworkSession) handle_mob_equipment(p proto.MobEquipmentPacket) ! {
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
			item_stack: proto.item_stack_from_descriptor_v2(p.item)
		}
		inventory_slot: int(p.slot)
		window_id:      int(p.container_id)
	}) {
		s.log.debug('Dropped mob equipment task - actor queue full')
	}
}

fn slot_change(container proto.FullContainerName, slot i8, count int, net_id int) SlotChange {
	return SlotChange{
		container: container
		info:      proto.ItemStackResponseSlotInfo{
			requested_slot:    slot
			slot:              slot
			amount:            i8(count)
			item_stack_net_id: if net_id != 0 { ?i32(i32(net_id)) } else { none }
			custom_name:       proto.RedactableString{}
		}
	}
}

fn stack_merge_compatible(a types.ItemStack, b types.ItemStack) bool {
	return a.id == b.id && a.meta == b.meta && a.block_runtime_id == b.block_runtime_id
		&& a.raw_extra_data == b.raw_extra_data
}

fn (mut s NetworkSession) handle_item_stack_request(p proto.ItemStackRequestPacket) ! {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	rid := s.runtime_id
	epoch := s.world_binding().epoch
	requests := p.requests
	responses := world_call[[]proto.ItemStackResponseInfo](mut wr, fn [rid, epoch, requests] (mut tx WorldTx) []proto.ItemStackResponseInfo {
		return process_item_stack_requests(mut tx, rid, epoch, requests)
	}) or { []proto.ItemStackResponseInfo{} }
	s.send_maybe_queued(&proto.ItemStackResponsePacket{
		responses: responses
	})!
}

fn process_item_stack_requests(mut tx WorldTx, runtime_id u64, epoch i64, requests []proto.RequestsEntry) []proto.ItemStackResponseInfo {
	mut target := tx.player_for_epoch(runtime_id, epoch) or {
		return []proto.ItemStackResponseInfo{}
	}
	mut out := []proto.ItemStackResponseInfo{}
	for request in requests {
		mut changes := []SlotChange{}
		for wire_action in request.actions {
			action := proto.item_stack_action(wire_action)
			match action {
				proto.TakeAction {
					changes << target.apply_move(action.source, action.destination, action.amount)
				}
				proto.PlaceAction {
					changes << target.apply_move(action.source, action.destination, action.amount)
				}
				proto.SwapAction {
					changes << target.apply_swap(action.source, action.destination)
				}
				proto.DestroyAction {
					changes << target.apply_remove(action.source, action.amount)
				}
				proto.DropAction {
					changes << target.apply_drop(mut tx.wr, action.source, action.amount)
				}
				proto.ConsumeAction {
					changes << target.apply_consume(mut tx.wr, action.source, action.amount)
				}
				proto.CraftCreativeAction {
					if target.player.game_mode() == proto.game_type_creative {
						target.set_pending_creative(int(action.creative_item_network_id))
					} else {
						target.player.set_pending_creative(none)
					}
				}
				proto.OtherAction {}
			}
		}
		persist_container_changes(mut tx, mut target, changes)
		out << proto.ItemStackResponseInfo{
			result:            proto.ItemStackNetResult.success
			has_containers:    true
			containers:        group_changes(changes)
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

// resolve_source_stack resolves a request source stack, falling back to the
// pending creative item for created output slots that are not tracked.
//
// This fallback applies to every action that may use that slot as a source,
// preventing creative swaps and moves from resolving it as empty.
fn (mut s NetworkSession) resolve_source_stack(container proto.FullContainerName, slot i8, raw_id int) (types.ItemStack, int, bool) {
	stack, net_id := s.resolve_request_stack(container, slot, raw_id)
	if stack.count == 0 {
		if pending := s.player.pending_creative() {
			return pending, 0, true
		}
	}
	return stack, net_id, false
}

fn (mut s NetworkSession) apply_move(src proto.ItemStackRequestSlotInfo, dst proto.ItemStackRequestSlotInfo, amount i8) []SlotChange {
	mut moved, src_net_id, from_creative := s.resolve_source_stack(src.container_name, src.slot,
		src.raw_id)
	mut take := int(amount)
	if take == 0 || take > moved.count {
		take = moved.count
	}
	dest_stack, dest_net_id := s.resolve_request_stack(dst.container_name, dst.slot, dst.raw_id)
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

	if src_net_id != 0 {
		s.player.delete_stack(src_net_id)
	}
	if dest_net_id != 0 {
		s.player.delete_stack(dest_net_id)
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

fn (mut s NetworkSession) apply_swap(src proto.ItemStackRequestSlotInfo, dst proto.ItemStackRequestSlotInfo) []SlotChange {
	a, src_net_id, a_from_creative := s.resolve_source_stack(src.container_name, src.slot,
		src.raw_id)
	b, dst_net_id, b_from_creative := s.resolve_source_stack(dst.container_name, dst.slot,
		dst.raw_id)
	if src_net_id != 0 {
		s.player.delete_stack(src_net_id)
	}
	if dst_net_id != 0 {
		s.player.delete_stack(dst_net_id)
	}
	if a_from_creative || b_from_creative {
		s.player.set_pending_creative(none)
	}
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

fn (mut s NetworkSession) apply_remove(src proto.ItemStackRequestSlotInfo, amount i8) []SlotChange {
	item, net_id, from_creative := s.resolve_source_stack(src.container_name, src.slot, src.raw_id)
	mut take := int(amount)
	if take == 0 || take > item.count {
		take = item.count
	}
	remaining := item.count - take
	if net_id != 0 {
		s.player.delete_stack(net_id)
	}
	if from_creative {
		s.player.set_pending_creative(none)
	}
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

fn (mut s NetworkSession) apply_drop(mut wr WorldRuntime, src proto.ItemStackRequestSlotInfo, amount i8) []SlotChange {
	item, _, _ := s.resolve_source_stack(src.container_name, src.slot, src.raw_id)
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
fn (mut s NetworkSession) apply_consume(mut wr WorldRuntime, src proto.ItemStackRequestSlotInfo, amount i8) []SlotChange {
	stack, net_id := s.resolve_request_stack(src.container_name, src.slot, src.raw_id)
	if stack.count == 0 {
		return []SlotChange{}
	}
	name := s.hub.data.item_name(stack.id)
	result := s.hub.items.consume_result(name, stack.meta) or { return s.apply_remove(src, amount) }
	for e in result.effects {
		s.apply_add_effect(mut wr, e)
	}
	return s.replace_consumed_stack(src, amount, stack, net_id, result)
}

fn (mut s NetworkSession) replace_consumed_stack(src proto.ItemStackRequestSlotInfo, amount i8, stack types.ItemStack, net_id int, result itemmod.ConsumeResult) []SlotChange {
	mut take := int(amount)
	if take == 0 || take > stack.count {
		take = stack.count
	}
	remaining := stack.count - take
	if net_id != 0 {
		s.player.delete_stack(net_id)
	}

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

fn group_changes(changes []SlotChange) []proto.ItemStackResponseContainerInfo {
	mut infos := []proto.ItemStackResponseContainerInfo{}
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
			infos << proto.ItemStackResponseContainerInfo{
				container_name: change.container
				slots:          [change.info]
			}
		}
	}
	return infos
}
