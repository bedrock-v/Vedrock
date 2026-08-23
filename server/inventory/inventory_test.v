module inventory

import protocol.types

fn test_track_stack_hands_out_unique_ids() {
	mut inv := new()
	first := inv.track_stack(types.ItemStack{ count: 1 })
	second := inv.track_stack(types.ItemStack{ count: 2 })
	assert first != second
	assert inv.stack(first)?.count == 1
	assert inv.stack(second)?.count == 2
}

fn test_stack_returns_none_for_an_unknown_id() {
	inv := new()
	if _ := inv.stack(7) {
		assert false, 'expected an unknown network id to return none'
	}
}

fn test_slots_resolve_through_the_network_id() {
	mut inv := new()
	net_id := inv.track_stack(types.ItemStack{ count: 5 })
	inv.set_slot(3, net_id)
	assert inv.has_slot(3)
	assert inv.slot(3)? == net_id
	assert inv.snapshot_slot_stacks()[3].count == 5
}

fn test_a_slot_pointing_at_a_deleted_stack_is_left_out() {
	mut inv := new()
	net_id := inv.track_stack(types.ItemStack{ count: 5 })
	inv.set_slot(3, net_id)
	inv.delete_stack(net_id)
	assert inv.snapshot_slot_stacks().len == 0
}

fn test_delete_slot_keeps_the_stack_tracked() {
	mut inv := new()
	net_id := inv.track_stack(types.ItemStack{ count: 5 })
	inv.set_slot(3, net_id)
	inv.delete_slot(3)
	assert !inv.has_slot(3)
	assert inv.stack(net_id)?.count == 5
}

fn test_clear_empties_both_stacks_and_slots() {
	mut inv := new()
	net_id := inv.track_stack(types.ItemStack{ count: 5 })
	inv.set_slot(0, net_id)
	inv.clear()
	assert inv.snapshot_slot_stacks().len == 0
	if _ := inv.stack(net_id) {
		assert false, 'expected the stack to be dropped'
	}
}

fn test_ids_are_not_reused_after_a_clear() {
	mut inv := new()
	first := inv.track_stack(types.ItemStack{})
	inv.clear()
	assert inv.track_stack(types.ItemStack{}) != first
}
