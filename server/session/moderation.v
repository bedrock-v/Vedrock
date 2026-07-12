module session

import protocol
import types

// op / deop

struct SetOpJob {
	runtime_id u64
	value      bool
}

fn (j SetOpJob) run(mut h Hub) {
	mut target := h.session_by_runtime(j.runtime_id) or { return }
	target.perm.set_op(j.value)
	if j.value {
		h.ops.add(target.identity.display_name) or {
			target.log.warn('Failed to persist op for ${target.identity.display_name}: ${err}')
		}
	} else {
		h.ops.remove(target.identity.display_name) or {
			target.log.warn('Failed to persist deop for ${target.identity.display_name}: ${err}')
		}
	}
	target.refresh_available_commands()
	target.refresh_abilities()
}

pub fn (mut s NetworkSession) set_operator(value bool) {
	s.hub.submit(SetOpJob{
		runtime_id: s.runtime_id
		value:      value
	})
}

// kill

struct KillJob {
	runtime_id u64
}

fn (j KillJob) run(mut h Hub) {
	mut target := h.session_by_runtime(j.runtime_id) or { return }
	if target.dead {
		return
	}
	target.health = 0
	target.transport.send(target.health_update()) or {}
	target.die('%death.attack.generic', [target.identity.display_name])
}

pub fn (mut s NetworkSession) kill() {
	s.hub.submit(KillJob{
		runtime_id: s.runtime_id
	})
}

// teleport

pub fn (mut s NetworkSession) position() (f32, f32, f32) {
	p := s.current_position()
	return p.x, p.y, p.z
}

struct TeleportJob {
	runtime_id u64
	x          f32
	y          f32
	z          f32
}

fn (j TeleportJob) run(mut h Hub) {
	mut target := h.session_by_runtime(j.runtime_id) or { return }
	target.apply_teleport(j.x, j.y, j.z)
}

fn (mut s NetworkSession) apply_teleport(x f32, y f32, z f32) {
	s.pos_mutex.lock()
	s.position = types.Vector3{x, y, z}
	s.prev_y = y
	s.vy = 0.0
	s.pos_mutex.unlock()
	s.transport.send(&protocol.MovePlayerPacket{
		actor_runtime_id: s.runtime_id
		position:         s.position
		pitch:            s.pitch
		yaw:              s.yaw
		head_yaw:         s.head_yaw
		mode:             protocol.move_player_mode_teleport
		on_ground:        false
	}) or {}
	s.hub.broadcast_except(s.runtime_id, s.move_actor_packet())
}

pub fn (mut s NetworkSession) teleport(x f32, y f32, z f32) {
	s.hub.submit(TeleportJob{
		runtime_id: s.runtime_id
		x:          x
		y:          y
		z:          z
	})
}

// clear inventory

struct ClearInventoryJob {
	runtime_id u64
}

fn (j ClearInventoryJob) run(mut h Hub) {
	mut target := h.session_by_runtime(j.runtime_id) or { return }
	target.apply_clear_inventory()
}

fn (mut s NetworkSession) apply_clear_inventory() {
	s.inv_stacks = map[int]types.ItemStack{}
	s.inv_slots = map[int]int{}
	mut items := []types.ItemStackWrapper{}
	for _ in 0 .. inventory_slot_count {
		items << empty_stack()
	}
	s.transport.send(&protocol.InventoryContentPacket{
		window_id:      inventory_window_id
		items:          items
		container_name: types.FullContainerName{
			container_id: 0
		}
		storage:        empty_stack()
	}) or {}
}

pub fn (mut s NetworkSession) clear_inventory() {
	s.hub.submit(ClearInventoryJob{
		runtime_id: s.runtime_id
	})
}

// give

// give_slot_count/give_hotbar_next implement a deliberately simplified slot
// pick for /give: the server doesn't currently keep a full slot->stack map in
// sync with client-driven inventory transactions (those are tracked by
// client-assigned network ids, not slot index), so building a "first empty
// slot" search would risk silently colliding with content the client already
// has and thinks the server doesn't know about. Round robining across the
// hotbar (0-8) via a dedicated counter avoids touching that unrelated
// bookkeeping; it can still overwrite a hotbar slot's visible content.
const give_hotbar_size = 9

struct GiveItemJob {
	runtime_id       u64
	numeric_id       int
	block_runtime_id int
	count            int
}

fn (j GiveItemJob) run(mut h Hub) {
	mut target := h.session_by_runtime(j.runtime_id) or { return }
	target.apply_give_item(j.numeric_id, j.block_runtime_id, j.count)
}

fn (mut s NetworkSession) apply_give_item(numeric_id int, block_runtime_id int, count int) {
	slot := s.give_next_slot % give_hotbar_size
	s.give_next_slot++
	stack := types.ItemStack{
		id:               numeric_id
		meta:             0
		count:            count
		block_runtime_id: block_runtime_id
		raw_extra_data:   []u8{}
	}
	net_id := s.track_stack(stack)
	s.inv_slots[slot] = net_id
	s.send_slot_update(slot, wrap_stack_id(stack, net_id))
}

pub fn (mut s NetworkSession) give_item(id string, count int) bool {
	numeric_id := s.hub.data.item_id(id)
	if numeric_id == 0 && id != 'minecraft:air' {
		return false
	}
	mut block_runtime_id := 0
	if it := s.hub.items.get(id) {
		block_runtime_id = it.block_runtime_id()
	}
	s.hub.submit(GiveItemJob{
		runtime_id:       s.runtime_id
		numeric_id:       numeric_id
		block_runtime_id: block_runtime_id
		count:            count
	})
	return true
}
