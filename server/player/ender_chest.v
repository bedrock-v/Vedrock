module player

import bedrock_v.protocol.types
import server.player.playerdb

// ender_slot_count is how many slots an ender chest shows. Every ender chest
// in the world is the same one for a given player, so its contents live here
// rather than at any of the blocks.
pub const ender_slot_count = 27

// ender_slots returns the whole ender chest in slot order, with an empty stack
// for every slot holding nothing.
pub fn (p &Player) ender_slots() []types.ItemStack {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut out := []types.ItemStack{len: ender_slot_count}
	for slot, stack in p.ender_items {
		if slot >= 0 && slot < ender_slot_count {
			out[slot] = stack
		}
	}
	return out
}

// set_ender_slot stores one slot, or empties it when the stack is nothing.
pub fn (mut p Player) set_ender_slot(slot int, stack types.ItemStack) {
	if slot < 0 || slot >= ender_slot_count {
		return
	}
	p.state_mutex.lock()
	if stack.count > 0 && stack.id != 0 {
		p.ender_items[slot] = stack
	} else {
		p.ender_items.delete(slot)
	}
	p.state_mutex.unlock()
}

// set_ender_items restores a saved ender chest.
pub fn (mut p Player) set_ender_items(items []playerdb.InvItem) {
	p.state_mutex.lock()
	p.ender_items = map[int]types.ItemStack{}
	for item in items {
		if item.slot < 0 || item.slot >= ender_slot_count || item.count <= 0 {
			continue
		}
		p.ender_items[item.slot] = types.ItemStack{
			id:               item.id
			meta:             item.meta
			count:            item.count
			block_runtime_id: item.block_runtime_id
			raw_extra_data:   item.raw_extra_data.clone()
		}
	}
	p.state_mutex.unlock()
}

// ender_items_for_save is the ender chest in the shape the save file wants.
pub fn (p &Player) ender_items_for_save() []playerdb.InvItem {
	mut out := []playerdb.InvItem{}
	for slot, stack in p.ender_slots() {
		if stack.count <= 0 || stack.id == 0 {
			continue
		}
		out << playerdb.InvItem{
			slot:             slot
			id:               stack.id
			meta:             stack.meta
			count:            stack.count
			block_runtime_id: stack.block_runtime_id
			raw_extra_data:   stack.raw_extra_data.clone()
		}
	}
	return out
}
