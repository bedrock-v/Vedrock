module session

import rand
import protocol.version.v662.enums as enums_662
import protocol.version.v944.packets as packets_944
import protocol.version.v944.types as types_944
import protocol.version.v944.enums as enums_944
import protocol.version.v975.types as types_975
import protocol.version.v1001.packets as packets_1001
import types
import server.entity
import server.internal.network
import server.world.db

const chest_dynamic_container_id = int(enums_662.ContainerID.first)

fn (s &NetworkSession) open_container_position() ?types.BlockPosition {
	mut m := s.open_container_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return s.open_container_pos
}

// set_open_container_position the session's open container tracking.
// Clearing always resets open_container_slot_net_ids in the same critical section.
fn (mut s NetworkSession) set_open_container_position(pos ?types.BlockPosition) {
	s.open_container_mutex.lock()
	s.open_container_pos = pos
	if pos == none {
		s.open_container_slot_net_ids = map[int]int{}
	}
	s.open_container_mutex.unlock()
}

// set_open_container_slots replaces the tracked slot->net_id map wholesale,
// called once, right after set_open_container_position with the net ids
// open_chest_container just minted for every non-empty slot.
fn (mut s NetworkSession) set_open_container_slots(net_ids map[int]int) {
	s.open_container_mutex.lock()
	s.open_container_slot_net_ids = net_ids.clone()
	s.open_container_mutex.unlock()
}

// open_container_slot_net_id returns the authoritative net id this session
// currently has tracked for one slot of its open container.
fn (s &NetworkSession) open_container_slot_net_id(slot int) int {
	mut m := s.open_container_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return s.open_container_slot_net_ids[slot] or { 0 }
}

// set_open_container_slot_net_id refreshes one slot's tracked net id after
// a mutation - called by persist_container_changes.
fn (mut s NetworkSession) set_open_container_slot_net_id(slot int, net_id int) {
	s.open_container_mutex.lock()
	s.open_container_slot_net_ids[slot] = net_id
	s.open_container_mutex.unlock()
}

fn (mut tx WorldTx) open_chest_container(mut s NetworkSession, pos types.BlockPosition) {
	if old := s.open_container_position() {
		tx.wr.world.release_container_hold(old.x, old.y, old.z, s.runtime_id)
		s.set_open_container_position(none)
	}
	if !tx.wr.world.try_hold_container(pos.x, pos.y, pos.z, s.runtime_id) {
		return
	}
	s.set_open_container_position(pos)
	stacks := tx.wr.world.container_slots(pos.x, pos.y, pos.z)
	mut descriptors := []types_975.NetworkItemStackDescriptorV2{cap: db.container_slot_count}
	mut slot_net_ids := map[int]int{}
	for slot, stack in stacks {
		if stack.count > 0 && stack.id != 0 {
			net_id := s.player.track_stack(stack)
			slot_net_ids[slot] = net_id
			descriptors << network.item_descriptor_v975_tracked(stack, net_id)
		} else {
			descriptors << network.item_descriptor_v975(stack)
		}
	}
	s.set_open_container_slots(slot_net_ids)
	s.deliver(&packets_944.ContainerOpenPacket{
		container_id:    enums_662.ContainerID.first
		container_type:  enums_662.ContainerType.container
		position:        network.block_pos_v944(pos)
		target_actor_id: network.actor_unique_id(-1)
	})
	s.deliver(&packets_1001.InventoryContentPacket{
		inventory_id:        u32(chest_dynamic_container_id)
		slots:               descriptors
		container_name_data: types_944.FullContainerName{
			container:  enums_944.ContainerEnumName.dynamic_container
			dynamic_id: i32(chest_dynamic_container_id)
		}
		storage_item:        network.item_descriptor_v975(types.ItemStack{})
	})
}

// close_chest_container releases s's hold ,if any, and clears its
// tracked open position. Safe to call even if nothing is open.
fn (mut s NetworkSession) close_chest_container(mut tx WorldTx) {
	if pos := s.open_container_position() {
		tx.wr.world.release_container_hold(pos.x, pos.y, pos.z, s.runtime_id)
	}
	s.set_open_container_position(none)
}

// drop_chest_contents spawns every non-empty stored stack at the chest's
// center, then clears its persisted contents.
fn drop_chest_contents(mut wr WorldRuntime, mut s NetworkSession, x int, y int, z int) {
	stacks := wr.world.container_slots(x, y, z)
	center := types.Vector3{f32(x) + 0.5, f32(y) + 0.5, f32(z) + 0.5}
	for stack in stacks {
		if stack.count <= 0 || stack.id == 0 {
			continue
		}
		max_stack := s.max_stack_size_for_numeric(stack.id)
		velocity := types.Vector3{
			x: (rand.f32() * 0.2) - 0.1
			y: 0.2
			z: (rand.f32() * 0.2) - 0.1
		}
		spawn_dropped_item_entity(mut wr, stack, max_stack, center, velocity,
			entity.item_pickup_delay_ticks)
	}
	wr.world.clear_container(x, y, z)
}
