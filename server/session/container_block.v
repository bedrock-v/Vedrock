module session

import rand
import bedrock_v.protocol.types
import server.block
import server.entity
import bedrock_v.protocol.current as proto
import server.worldrt

fn chest_dynamic_container_id() int {
	return int(proto.ContainerID.first)
}

// OpenContainer is the container a session currently has open: which kind it
// is and the block it was opened from.
struct OpenContainer {
	kind block.ContainerKind
	pos  types.BlockPosition
}

fn (s &NetworkSession) open_container() ?OpenContainer {
	mut m := s.open_container_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return s.open_container
}

// open_container_position is the block a session opened its container from,
// which is what the world's per-position hold is keyed by.
fn (s &NetworkSession) open_container_position() ?types.BlockPosition {
	container := s.open_container() or { return none }
	return container.pos
}

// set_open_container updates the session's open container tracking. Clearing
// always resets open_container_slot_net_ids in the same critical section.
fn (mut s NetworkSession) set_open_container(container ?OpenContainer) {
	s.open_container_mutex.lock()
	s.open_container = container
	if container == none {
		s.open_container_slot_net_ids = map[int]int{}
	}
	s.open_container_mutex.unlock()
}

// set_open_container_slots replaces the tracked slot->net_id map wholesale,
// called once, right after set_open_container with the net ids
// open_container_block just minted for every non-empty slot.
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

// open_container_block opens whatever container the block at pos is.
fn open_container_block(mut tx worldrt.WorldTx, mut s NetworkSession, pos types.BlockPosition, kind block.ContainerKind) {
	s.close_open_container(mut tx)
	if !s.hold_container(mut tx, kind, pos) {
		return
	}
	container := OpenContainer{
		kind: kind
		pos:  pos
	}
	s.set_open_container(container)
	s.send_container_contents(mut tx, container)
}

// hold_container claims the block for this session, so nobody else can open it
// while it is in use. A player scoped container is nobody else's to claim.
fn (mut s NetworkSession) hold_container(mut tx worldrt.WorldTx, kind block.ContainerKind, pos types.BlockPosition) bool {
	if kind.player_scoped {
		return true
	}
	return tx.wr.world.try_hold_container(pos.x, pos.y, pos.z, s.runtime_id)
}

// container_stacks reads the container's contents in slot order.
fn (s &NetworkSession) container_stacks(mut tx worldrt.WorldTx, container OpenContainer) []types.ItemStack {
	if container.kind.player_scoped {
		return s.player.ender_slots()
	}
	return tx.wr.world.container_slots(container.pos.x, container.pos.y, container.pos.z)
}

fn (mut s NetworkSession) send_container_contents(mut tx worldrt.WorldTx, container OpenContainer) {
	stacks := s.container_stacks(mut tx, container)
	mut descriptors := []proto.NetworkItemStackDescriptorV2{cap: stacks.len}
	mut slot_net_ids := map[int]int{}
	for slot, stack in stacks {
		if stack.count > 0 && stack.id != 0 {
			net_id := s.player.track_stack(stack)
			slot_net_ids[slot] = net_id
			descriptors << proto.item_descriptor_v2_tracked(stack, net_id)
		} else {
			descriptors << proto.item_descriptor_v2(stack)
		}
	}
	s.set_open_container_slots(slot_net_ids)
	s.deliver(&proto.ContainerOpenPacket{
		container_id:    proto.ContainerID.first
		container_type:  proto.ContainerType.container
		position:        proto.block_pos(container.pos)
		target_actor_id: proto.actor_unique_id(-1)
	})
	s.deliver(&proto.InventoryContentPacket{
		inventory_id:        u32(chest_dynamic_container_id())
		slots:               descriptors
		container_name_data: proto.FullContainerName{
			container:  proto.ContainerEnumName.dynamic_container
			dynamic_id: i32(chest_dynamic_container_id())
		}
		storage_item:        proto.item_descriptor_v2(types.ItemStack{})
	})
}

// store_container_slot writes one slot back to wherever that container keeps
// its contents.
fn (mut s NetworkSession) store_container_slot(mut tx worldrt.WorldTx, container OpenContainer, slot int, stack types.ItemStack) {
	if slot < 0 || slot >= container.kind.slots {
		return
	}
	if container.kind.player_scoped {
		s.player.set_ender_slot(slot, stack)
		return
	}
	pos := container.pos
	tx.wr.world.set_container_slot(pos.x, pos.y, pos.z, slot, stack)
}

// close_open_container releases s's holds, if any, and clears its tracked open
// container. Safe to call even if nothing is open.
fn (mut s NetworkSession) close_open_container(mut tx worldrt.WorldTx) {
	if container := s.open_container() {
		if !container.kind.player_scoped {
			tx.wr.world.release_container_hold(container.pos.x, container.pos.y, container.pos.z,
				s.runtime_id)
		}
	}
	s.set_open_container(none)
}

// drop_container_contents spawns every non-empty stored stack at the block's
// center, then clears its persisted contents. An ender chest drops nothing:
// what it shows belongs to the player, not to the block.
fn drop_container_contents(mut tx worldrt.WorldTx, mut s NetworkSession, x int, y int, z int) {
	stacks := tx.wr.world.container_slots(x, y, z)
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
		spawn_dropped_item_entity(mut tx, stack, max_stack, center, velocity,
			entity.item_pickup_delay_ticks)
	}
	tx.wr.world.clear_container(x, y, z)
}
