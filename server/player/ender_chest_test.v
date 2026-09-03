module player

import bedrock_v.protocol.types

fn diamond_stack(count int) types.ItemStack {
	return types.ItemStack{
		id:    264
		count: count
	}
}

fn test_an_ender_chest_starts_empty() {
	p := new_player()
	slots := p.ender_slots()
	assert slots.len == ender_slot_count
	for stack in slots {
		assert stack.count == 0
	}
}

fn test_storing_and_clearing_a_slot() {
	mut p := new_player()
	p.set_ender_slot(3, diamond_stack(5))
	assert p.ender_slots()[3].count == 5

	p.set_ender_slot(3, types.ItemStack{})
	assert p.ender_slots()[3].count == 0
}

fn test_slots_outside_the_chest_are_ignored() {
	mut p := new_player()
	p.set_ender_slot(-1, diamond_stack(1))
	p.set_ender_slot(ender_slot_count, diamond_stack(1))
	for stack in p.ender_slots() {
		assert stack.count == 0
	}
}

fn test_an_ender_chest_survives_a_save_and_load() {
	mut p := new_player()
	p.set_ender_slot(0, diamond_stack(2))
	p.set_ender_slot(26, diamond_stack(7))
	saved := p.ender_items_for_save()
	assert saved.len == 2

	mut restored := new_player()
	restored.set_ender_items(saved)
	slots := restored.ender_slots()
	assert slots[0].count == 2
	assert slots[26].count == 7
	assert slots[1].count == 0
}
