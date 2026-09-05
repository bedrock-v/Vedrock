module player

import bedrock_v.protocol.types

// armor_slot_count is how many pieces a player wears, ordered helmet,
// chestplate, leggings, boots - the order the client sends them in.
pub const armor_slot_count = 4

// armor_slot_base is where the worn pieces sit in the same slot map as the
// carried inventory. Keeping them in one map means equipment gets the same
// stack tracking, persistence and lookup path the rest of the inventory
// already has, instead of a parallel one that has to be kept in step with it.
pub const armor_slot_base = inventory_slot_count

// armor_window_id is the container id the client addresses the worn pieces
// by, distinct from the inventory window.
pub const armor_window_id = 120

// tracked_slot_count is every slot a player's stacks can live in: the carried
// inventory plus the worn pieces.
pub const tracked_slot_count = armor_slot_base + armor_slot_count

// armor_slot maps an armor index (0-3) onto its inventory slot.
pub fn armor_slot(index int) int {
	return armor_slot_base + index
}

// is_armor_slot reports whether slot addresses a worn piece rather than a
// carried one.
pub fn is_armor_slot(slot int) bool {
	return slot >= armor_slot_base && slot < armor_slot_base + armor_slot_count
}

// armor_stack returns the piece worn at index, or none when that slot is
// empty.
pub fn (p &Player) armor_stack(index int) ?types.ItemStack {
	net := p.inv_slot(armor_slot(index)) or { return none }
	return p.inv_stack(net)
}

// send_armor_slot_update keeps the client's view of one worn piece in sync
// after the server changed it.
pub fn (mut p Player) send_armor_slot_update(index int, wrapped types.ItemStackWrapper) {
	mut sink := p.sink
	sink.send_armor_slot_update(index, wrapped)
}
