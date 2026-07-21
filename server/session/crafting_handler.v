module session

import protocol
import protocol.types

// Absolute slot indices for the workbench window. Container 13 (crafting
// input) slots are 32-40; container 14 (crafting output) is slot 50.
const crafting_input_base = u8(32)
const crafting_output_slot = u8(50)

// return_crafting_items moves all items from the crafting grid back to the
// player inventory. Called when the crafting container is closed.
fn (mut s NetworkSession) return_crafting_items() {
	if s.crafting_output != 0 {
		result := s.inv_stacks[s.crafting_output] or { types.ItemStack{} }
		if result.count > 0 {
			s.merge_into_inventory(result)
		}
	}
	for _, net_id in s.crafting_input {
		stack := s.inv_stacks[net_id] or { continue }
		if stack.count > 0 {
			s.merge_into_inventory(stack)
		}
	}
	s.clear_crafting_grid()
}

fn (mut s NetworkSession) clear_crafting_grid() {
	s.inv_stacks.delete(s.crafting_output)
	s.crafting_output = 0
	for _, net_id in s.crafting_input {
		s.inv_stacks.delete(net_id)
	}
	s.crafting_input = map[u8]int{}
}

// merge_into_inventory places a stack into the player inventory without
// sending updates. The caller is responsible for syncing the client.
fn (mut s NetworkSession) merge_into_inventory(stack types.ItemStack) {
	mut remaining := stack.count
	for flat in 0 .. inventory_slot_count {
		if remaining <= 0 {
			break
		}
		net_id := s.inv_slots[flat] or { continue }
		existing := s.inv_stacks[net_id] or { continue }
		if existing.id != stack.id || existing.meta != stack.meta {
			continue
		}
		max := s.max_stack_size_for_numeric(existing.id)
		space := max - existing.count
		if space <= 0 {
			continue
		}
		mut add := remaining
		if add > space {
			add = space
		}
		s.inv_stacks.delete(net_id)
		mut merged := existing
		merged.count += add
		new_net := s.track_stack(merged)
		s.inv_slots[flat] = new_net
		remaining -= add
	}
	for flat in 0 .. inventory_slot_count {
		if remaining <= 0 {
			break
		}
		if flat in s.inv_slots {
			continue
		}
		max := s.max_stack_size_for_numeric(stack.id)
		mut add := remaining
		if add > max {
			add = max
		}
		mut placed := stack
		placed.count = add
		new_net := s.track_stack(placed)
		s.inv_slots[flat] = new_net
		remaining -= add
	}
}
