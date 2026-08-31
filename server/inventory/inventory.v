module inventory

import bedrock_v.protocol.types
import sync

// Inventory holds the item stacks a player carries. A stack is tracked by the
// network id the client knows it as, and a slot points at the network id it
// currently holds, so a stack keeps its identity while it moves between slots.
//
// Every method is safe to call from several threads: the inventory carries its
// own lock rather than borrowing the owner's.
@[heap]
pub struct Inventory {
mut:
	mutex   &sync.Mutex = sync.new_mutex()
	stacks  map[int]types.ItemStack
	slots   map[int]int
	next_id int = 1
}

// new returns an empty Inventory.
pub fn new() Inventory {
	return Inventory{
		stacks: map[int]types.ItemStack{}
		slots:  map[int]int{}
	}
}

// stack returns the stack tracked under net_id, or none if that id is unknown.
pub fn (inv &Inventory) stack(net_id int) ?types.ItemStack {
	mut m := inv.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return inv.stacks[net_id] or { return none }
}

// put_stack stores stack under net_id, replacing whatever that id tracked.
pub fn (mut inv Inventory) put_stack(net_id int, stack types.ItemStack) {
	inv.mutex.lock()
	inv.stacks[net_id] = stack
	inv.mutex.unlock()
}

// delete_stack stops tracking the stack under net_id.
pub fn (mut inv Inventory) delete_stack(net_id int) {
	inv.mutex.lock()
	inv.stacks.delete(net_id)
	inv.mutex.unlock()
}

// track_stack stores stack under a freshly allocated network id and returns
// that id. It is the only place the id counter advances.
pub fn (mut inv Inventory) track_stack(stack types.ItemStack) int {
	inv.mutex.lock()
	defer {
		inv.mutex.unlock()
	}
	net_id := inv.next_id
	inv.next_id++
	inv.stacks[net_id] = stack
	return net_id
}

// slot returns the network id held by slot, or none if the slot is empty.
pub fn (inv &Inventory) slot(slot int) ?int {
	mut m := inv.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return inv.slots[slot] or { return none }
}

// has_slot reports whether slot currently holds a stack.
pub fn (inv &Inventory) has_slot(slot int) bool {
	mut m := inv.mutex
	m.lock()
	defer {
		m.unlock()
	}
	return slot in inv.slots
}

// set_slot points slot at the stack tracked under net_id.
pub fn (mut inv Inventory) set_slot(slot int, net_id int) {
	inv.mutex.lock()
	inv.slots[slot] = net_id
	inv.mutex.unlock()
}

// delete_slot empties slot, leaving the stack itself tracked.
pub fn (mut inv Inventory) delete_slot(slot int) {
	inv.mutex.lock()
	inv.slots.delete(slot)
	inv.mutex.unlock()
}

// snapshot_slot_stacks returns the slot layout with the network id
// indirection already resolved, so callers see one consistent view.
pub fn (inv &Inventory) snapshot_slot_stacks() map[int]types.ItemStack {
	mut m := inv.mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut out := map[int]types.ItemStack{}
	for slot, net_id in inv.slots {
		if stack := inv.stacks[net_id] {
			out[slot] = stack
		}
	}
	return out
}

// clear drops every stack and every slot, leaving the id counter alone so
// stacks handed out earlier can never be confused with new ones.
pub fn (mut inv Inventory) clear() {
	inv.mutex.lock()
	inv.stacks = map[int]types.ItemStack{}
	inv.slots = map[int]int{}
	inv.mutex.unlock()
}
