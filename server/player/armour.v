module player

import bedrock_v.protocol.types
import bedrock_v.protocol.current as proto

// armour_slot_count is how many pieces a player wears, ordered helmet,
// chestplate, leggings, boots - the order the client sends them in.
pub const armour_slot_count = 4

// armour_slot_base is where the worn pieces sit in the same slot map as the
// carried inventory. Keeping them in one map means equipment gets the same
// stack tracking, persistence and lookup path the rest of the inventory
// already has, instead of a parallel one that has to be kept in step with it.
pub const armour_slot_base = inventory_slot_count

// armour_window_id is the container id the client addresses the worn pieces
// by, distinct from the inventory window.
pub const armour_window_id = 120

// tracked_slot_count is every slot a player's stacks can live in: the carried
// inventory plus the worn pieces.
pub const tracked_slot_count = armour_slot_base + armour_slot_count

// armour_slot maps an armour index (0-3) onto its inventory slot.
pub fn armour_slot(index int) int {
	return armour_slot_base + index
}

// is_armour_slot reports whether slot addresses a worn piece rather than a
// carried one.
pub fn is_armour_slot(slot int) bool {
	return slot >= armour_slot_base && slot < armour_slot_base + armour_slot_count
}

// armour_stack returns the piece worn at index, or none when that slot is
// empty.
pub fn (p &Player) armour_stack(index int) ?types.ItemStack {
	net := p.inv_slot(armour_slot(index)) or { return none }
	return p.inv_stack(net)
}

// send_armour_slot_update keeps the client's view of one worn piece in sync
// after the server changed it.
pub fn (mut p Player) send_armour_slot_update(index int, wrapped types.ItemStackWrapper) {
	mut sink := p.sink
	sink.deliver(&proto.InventorySlotPacket{
		container_id:        u32(armour_window_id)
		slot:                u32(index)
		container_name_data: proto.FullContainerName{
			container: .armor_container
		}
		item:                proto.item_descriptor_v2_tracked(wrapped.item_stack, wrapped.stack_id)
	})
}
