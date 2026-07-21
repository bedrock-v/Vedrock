module session

import math
import protocol
import protocol.types

const break_pickup_delay = i64(10)
const drop_pickup_delay = i64(40)

fn (s &NetworkSession) drops_on_break() bool {
	return s.game_mode != protocol.game_type_creative
		&& s.game_mode != protocol.game_type_creative_spectator
}

fn (mut s NetworkSession) drop_block_item(pos types.BlockPosition, block_id int) {
	item_id := s.hub.data.item_for_block(block_id)
	if item_id == 0 {
		return
	}
	mut block_runtime := 0
	name := s.hub.data.item_name(item_id)
	if it := s.hub.items.get(name) {
		block_runtime = it.block_runtime_id()
	}
	stack := types.ItemStack{
		id:               item_id
		count:            1
		block_runtime_id: block_runtime
		raw_extra_data:   []u8{}
	}
	s.hub.drop_item(stack, f32(pos.x) + 0.5, f32(pos.y) + 0.5, f32(pos.z) + 0.5, 0.0, 0.15,
		0.0, break_pickup_delay)
}

fn (mut s NetworkSession) throw_item(stack types.ItemStack) {
	if stack.id == 0 || stack.count <= 0 {
		return
	}
	pos := s.current_position()
	yaw_rad := f64(s.yaw) * math.pi / 180.0
	pitch_rad := f64(s.pitch) * math.pi / 180.0
	fx := f32(-math.sin(yaw_rad) * math.cos(pitch_rad))
	fy := f32(-math.sin(pitch_rad))
	fz := f32(math.cos(yaw_rad) * math.cos(pitch_rad))
	drop_x := pos.x + fx * 0.3
	drop_y := pos.y - 0.3
	drop_z := pos.z + fz * 0.3
	s.hub.drop_item(stack, drop_x, drop_y, drop_z, fx * 0.3, fy * 0.3 + 0.1, fz * 0.3,
		drop_pickup_delay)
}

fn (mut s NetworkSession) apply_pickup(stack types.ItemStack) bool {
	if stack.id == 0 || stack.count <= 0 {
		return true
	}
	max := s.max_stack_size_for_numeric(stack.id)
	mut needed := stack.count

	mut merge_plan := map[int]int{}
	for slot, net in s.inv_slots {
		existing := s.inv_stacks[net] or { continue }
		if existing.id != stack.id || existing.meta != stack.meta {
			continue
		}
		space := max - existing.count
		if space <= 0 {
			continue
		}
		add := if space < needed { space } else { needed }
		merge_plan[slot] = add
		needed -= add
		if needed == 0 {
			break
		}
	}

	mut new_slots := []int{}
	if needed > 0 {
		for slot in 0 .. inventory_slot_count {
			if slot in s.inv_slots {
				continue
			}
			new_slots << slot
			needed -= if needed < max { needed } else { max }
			if needed <= 0 {
				break
			}
		}
	}

	if needed > 0 {
		return false
	}

	mut remaining := stack.count
	for slot, add in merge_plan {
		net := s.inv_slots[slot] or { continue }
		mut existing := s.inv_stacks[net] or { continue }
		existing.count += add
		s.inv_stacks[net] = existing
		s.send_slot_update(slot, wrap_stack_id(existing, net))
		remaining -= add
	}

	for slot in new_slots {
		if remaining <= 0 {
			break
		}
		put := if remaining < max { remaining } else { max }
		mut placed := stack
		placed.count = put
		net := s.track_stack(placed)
		s.inv_slots[slot] = net
		s.send_slot_update(slot, wrap_stack_id(placed, net))
		remaining -= put
	}
	return true
}
