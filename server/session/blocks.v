module session

import math
import protocol
import protocol.types
import protocol.enums
import server.world

fn (s &NetworkSession) block_at(x int, y int, z int) int {
	if id := s.hub.world_block_override(x, y, z) {
		return id
	}
	return s.generator.block_at(x, y, z)
}

fn face_offset(pos types.BlockPosition, face int) types.BlockPosition {
	return match face {
		0 { types.BlockPosition{pos.x, pos.y - 1, pos.z} }
		1 { types.BlockPosition{pos.x, pos.y + 1, pos.z} }
		2 { types.BlockPosition{pos.x, pos.y, pos.z - 1} }
		3 { types.BlockPosition{pos.x, pos.y, pos.z + 1} }
		4 { types.BlockPosition{pos.x - 1, pos.y, pos.z} }
		5 { types.BlockPosition{pos.x + 1, pos.y, pos.z} }
		else { pos }
	}
}

fn (mut s NetworkSession) handle_inventory_transaction(p protocol.InventoryTransactionPacket) ! {
	if p.transaction_type == protocol.inventory_transaction_type_use_item_on_entity {
		ue := p.use_item_on_entity
		if ue.action_type == protocol.item_use_on_entity_action_attack {
			s.handle_attack(ue.target_entity_runtime_id, ue.held_item)!
		}
		return
	}
	if p.transaction_type != protocol.inventory_transaction_type_use_item {
		return
	}
	ut := p.use_item
	match ut.action_type {
		protocol.item_use_action_click_block {
			runtime_id := ut.held_item.item_stack.block_runtime_id
			if runtime_id == 0 {
				return
			}
			target := face_offset(ut.block_position, int(ut.block_face))
			if s.place_block(target, runtime_id)! && s.game_mode != protocol.game_type_creative {
				s.consume_held_item()
			}
		}
		protocol.item_use_action_destroy_block {
			s.break_block(ut.block_position)!
		}
		else {}
	}
}

fn (mut s NetworkSession) handle_player_action(p protocol.PlayerActionPacket) ! {
	match p.action {
		int(enums.PlayerAction.creative_player_destroy_block),
		int(enums.PlayerAction.predict_destroy_block) {
			s.break_block(p.block_position)!
		}
		int(enums.PlayerAction.start_break) {
			s.broadcast_swing()
		}
		int(enums.PlayerAction.respawn) {
			s.respawn()
		}
		else {}
	}
}

fn (mut s NetworkSession) place_block(pos types.BlockPosition, runtime_id int) !bool {
	if s.block_at(pos.x, pos.y, pos.z) != world.air.network_id || s.intersects_player(pos) {
		s.transport.send(&protocol.UpdateBlockPacket{
			block_position:   pos
			block_runtime_id: s.block_at(pos.x, pos.y, pos.z)
			flags:            protocol.update_block_flag_network
			data_layer_id:    0
		})!
		return false
	}
	s.hub.set_world_block(pos.x, pos.y, pos.z, runtime_id)
	s.broadcast_block_update(pos, runtime_id)
	s.broadcast_swing()
	return true
}

fn (mut s NetworkSession) consume_held_item() {
	stack, net := s.inventory_stack_at(s.held_slot)
	if net == 0 || stack.count <= 0 {
		return
	}
	s.inv_stacks.delete(net)
	mut wrapped := empty_stack()
	if stack.count > 1 {
		mut remaining := stack
		remaining.count -= 1
		new_net := s.track_stack(remaining)
		s.inv_slots[s.held_slot] = new_net
		wrapped = wrap_stack_id(remaining, new_net)
	} else {
		s.inv_slots.delete(s.held_slot)
	}
	s.held_item = wrapped
	s.send_slot_update(s.held_slot, wrapped)
}

fn (s &NetworkSession) intersects_player(pos types.BlockPosition) bool {
	px := int(math.floor(s.position.x))
	py := int(math.floor(s.position.y - player_eye_height))
	pz := int(math.floor(s.position.z))
	if pos.x != px || pos.z != pz {
		return false
	}
	return pos.y == py || pos.y == py + 1
}

fn (mut s NetworkSession) break_block(pos types.BlockPosition) ! {
	old_id := s.block_at(pos.x, pos.y, pos.z)
	air_id := world.air.network_id
	if old_id == air_id {
		return
	}
	s.hub.set_world_block(pos.x, pos.y, pos.z, air_id)
	s.broadcast_block_update(pos, air_id)
	s.broadcast_destroy_particles(pos, old_id)
	s.broadcast_swing()
}

fn (mut s NetworkSession) broadcast_destroy_particles(pos types.BlockPosition, runtime_id int) {
	s.hub.broadcast(&protocol.LevelEventPacket{
		event_id:   protocol.level_event_particles_destroy_block
		position:   types.Vector3{f32(pos.x) + 0.5, f32(pos.y) + 0.5, f32(pos.z) + 0.5}
		event_data: runtime_id
	})
}

fn (mut s NetworkSession) broadcast_block_update(pos types.BlockPosition, runtime_id int) {
	s.hub.broadcast(&protocol.UpdateBlockPacket{
		block_position:   pos
		block_runtime_id: runtime_id
		flags:            protocol.update_block_flag_network
		data_layer_id:    0
	})
}

fn (mut s NetworkSession) broadcast_swing() {
	s.hub.broadcast_except(s.runtime_id, &protocol.AnimatePacket{
		action:           protocol.animate_action_swing_arm
		actor_runtime_id: s.runtime_id
	})
}

fn (mut s NetworkSession) handle_block_pick_request(p protocol.BlockPickRequestPacket) ! {
	runtime_id := s.block_at(p.block_position.x, p.block_position.y, p.block_position.z)
	if runtime_id == world.air.network_id {
		return
	}
	item_id := s.hub.data.item_for_block(runtime_id)
	if item_id == 0 {
		return
	}

	if existing_slot := s.find_inventory_slot(item_id, runtime_id) {
		if existing_slot < give_hotbar_size {
			stack, net := s.inventory_stack_at(existing_slot)
			s.select_hotbar_slot(existing_slot, wrap_stack_id(stack, net))
		} else {
			s.swap_slot_into_hand(existing_slot)
		}
		return
	}
	if s.game_mode != protocol.game_type_creative {
		return
	}

	stack := types.ItemStack{
		id:               item_id
		count:            1
		block_runtime_id: runtime_id
	}
	empty_slot := s.first_empty_slot() or {
		net_id := s.track_stack(stack)
		s.inv_slots[s.held_slot] = net_id
		s.select_hotbar_slot(s.held_slot, wrap_stack_id(stack, net_id))
		return
	}
	if empty_slot < give_hotbar_size {
		net_id := s.track_stack(stack)
		s.inv_slots[empty_slot] = net_id
		wrapped := wrap_stack_id(stack, net_id)
		s.send_slot_update(empty_slot, wrapped)
		s.select_hotbar_slot(empty_slot, wrapped)
		return
	}
	held, held_net := s.inventory_stack_at(s.held_slot)
	if held_net == 0 {
		s.inv_slots.delete(empty_slot)
	} else {
		s.inv_slots[empty_slot] = held_net
	}
	s.send_slot_update(empty_slot, wrap_stack_id(held, held_net))
	net_id := s.track_stack(stack)
	s.inv_slots[s.held_slot] = net_id
	s.select_hotbar_slot(s.held_slot, wrap_stack_id(stack, net_id))
}

fn (s &NetworkSession) find_inventory_slot(item_id int, runtime_id int) ?int {
	for slot in 0 .. inventory_slot_count {
		net := s.inv_slots[slot] or { continue }
		existing := s.inv_stacks[net] or { continue }
		if existing.id == item_id && existing.block_runtime_id == runtime_id {
			return slot
		}
	}
	return none
}

fn (mut s NetworkSession) swap_slot_into_hand(slot int) {
	picked, picked_net := s.inventory_stack_at(slot)
	held, held_net := s.inventory_stack_at(s.held_slot)
	if held_net == 0 {
		s.inv_slots.delete(slot)
	} else {
		s.inv_slots[slot] = held_net
	}
	s.send_slot_update(slot, wrap_stack_id(held, held_net))
	if picked_net == 0 {
		s.inv_slots.delete(s.held_slot)
	} else {
		s.inv_slots[s.held_slot] = picked_net
	}
	s.select_hotbar_slot(s.held_slot, wrap_stack_id(picked, picked_net))
}

fn (mut s NetworkSession) select_hotbar_slot(slot int, wrapped types.ItemStackWrapper) {
	s.held_item = wrapped
	s.held_slot = slot
	s.transport.send(&protocol.PlayerHotbarPacket{
		selected_hotbar_slot: slot
		window_id:            inventory_window_id
		select_hotbar_slot:   true
	}) or {}
	s.hub.broadcast_except(s.runtime_id, &protocol.MobEquipmentPacket{
		actor_runtime_id: s.runtime_id
		item:             wrapped
		inventory_slot:   slot
		hotbar_slot:      slot
		window_id:        inventory_window_id
	})
}
