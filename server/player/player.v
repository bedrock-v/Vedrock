module player

import server.internal.auth
import server.permission
import server.effect
import server.player.playerdb
import protocol.types
import sync

// Player holds the gamestate fields that belong to a player as an entity,
// independent of whichever network connection (if any) is currently driving
// it. It holds no transport/packet send capability by design.
//
// Behavior methods that need to send a packet or broadcast (send_message,
// teleport, kill, give_item, etc.) stay on NetworkSession, which reads and
// writes through this struct's accessors for the state they operate on.
@[heap]
pub struct Player {
pub mut:
	identity auth.Identity
	perm     permission.Permissible
mut:
	// state_mutex guards the mutable player state below, excluding fields
	// covered by their own mutexes. State accessors must hold this lock because
	// player state may now be accessed from multiple actor threads.
	state_mutex      &sync.Mutex = sync.new_mutex()
	game_mode        int
	health           f32 = 20.0
	dead             bool
	held_item        types.ItemStackWrapper
	held_slot        int
	inv_stacks       map[int]types.ItemStack
	inv_slots        map[int]int
	inv_next_id      int = 1
	pending_creative ?types.ItemStack
	loaded_items     []playerdb.InvItem
	effects          effect.Manager
	has_last_death   bool
	last_death_pos   types.Vector3
	pos_mutex        &sync.Mutex = sync.new_mutex()
	position         types.Vector3
	pitch            f32
	yaw              f32
	head_yaw         f32
	vy               f32
	prev_y           f32
}

pub fn new_player() &Player {
	return &Player{
		inv_stacks: map[int]types.ItemStack{}
		inv_slots:  map[int]int{}
		effects:    effect.new_manager()
	}
}

pub fn (p &Player) name() string {
	return p.identity.display_name
}

pub fn (p &Player) has_permission(name string) bool {
	return p.perm.has_permission(name)
}

pub fn (p &Player) game_mode() int {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.game_mode
}

pub fn (mut p Player) set_game_mode(mode int) {
	p.state_mutex.lock()
	p.game_mode = mode
	p.state_mutex.unlock()
}

pub fn (p &Player) health() f32 {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.health
}

pub fn (mut p Player) set_health(value f32) {
	p.state_mutex.lock()
	p.health = value
	p.state_mutex.unlock()
}

pub fn (p &Player) is_dead() bool {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.dead
}

pub fn (mut p Player) set_dead(value bool) {
	p.state_mutex.lock()
	p.dead = value
	p.state_mutex.unlock()
}

pub fn (p &Player) held_item() types.ItemStackWrapper {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.held_item
}

pub fn (p &Player) held_slot() int {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.held_slot
}

// set_held updates the held slot and its wrapper together. Every current
// caller sets both at once.
pub fn (mut p Player) set_held(slot int, item types.ItemStackWrapper) {
	p.state_mutex.lock()
	p.held_slot = slot
	p.held_item = item
	p.state_mutex.unlock()
}

pub fn (p &Player) inv_stack(net_id int) ?types.ItemStack {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.inv_stacks[net_id] or { return none }
}

pub fn (mut p Player) put_stack(net_id int, stack types.ItemStack) {
	p.state_mutex.lock()
	p.inv_stacks[net_id] = stack
	p.state_mutex.unlock()
}

pub fn (mut p Player) delete_stack(net_id int) {
	p.state_mutex.lock()
	p.inv_stacks.delete(net_id)
	p.state_mutex.unlock()
}

pub fn (p &Player) inv_slot(slot int) ?int {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.inv_slots[slot] or { return none }
}

pub fn (p &Player) has_slot(slot int) bool {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return slot in p.inv_slots
}

pub fn (mut p Player) set_slot(slot int, net_id int) {
	p.state_mutex.lock()
	p.inv_slots[slot] = net_id
	p.state_mutex.unlock()
}

pub fn (mut p Player) delete_slot(slot int) {
	p.state_mutex.lock()
	p.inv_slots.delete(slot)
	p.state_mutex.unlock()
}

// snapshot_slot_stacks returns a cloned map of inventory slot to item stack.
// The network-id indirection is resolved while holding state_mutex so callers
// get a consistent slot layout.
pub fn (p &Player) snapshot_slot_stacks() map[int]types.ItemStack {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	mut out := map[int]types.ItemStack{}
	for slot, net_id in p.inv_slots {
		if stack := p.inv_stacks[net_id] {
			out[slot] = stack
		}
	}
	return out
}

// track_stack assigns stack a new network ID, stores it and returns that ID.
// It is the only method that reads or advances inv_next_id.
pub fn (mut p Player) track_stack(stack types.ItemStack) int {
	p.state_mutex.lock()
	defer {
		p.state_mutex.unlock()
	}
	id := p.inv_next_id
	p.inv_next_id++
	p.inv_stacks[id] = stack
	return id
}

pub fn (mut p Player) clear_inventory() {
	p.state_mutex.lock()
	p.inv_stacks = map[int]types.ItemStack{}
	p.inv_slots = map[int]int{}
	p.state_mutex.unlock()
}

pub fn (p &Player) pending_creative() ?types.ItemStack {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.pending_creative
}

pub fn (mut p Player) set_pending_creative(stack ?types.ItemStack) {
	p.state_mutex.lock()
	p.pending_creative = stack
	p.state_mutex.unlock()
}

pub fn (mut p Player) set_loaded_items(items []playerdb.InvItem) {
	p.state_mutex.lock()
	p.loaded_items = items
	p.state_mutex.unlock()
}

pub fn (p &Player) loaded_items_len() int {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.loaded_items.len
}

pub fn (p &Player) loaded_item(i int) playerdb.InvItem {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.loaded_items[i]
}

pub fn (mut p Player) add_effect_result(e effect.Effect) effect.AddResult {
	p.state_mutex.lock()
	defer {
		p.state_mutex.unlock()
	}
	return p.effects.add_result(e)
}

pub fn (mut p Player) remove_effect(typ effect.Type) ?effect.Effect {
	p.state_mutex.lock()
	defer {
		p.state_mutex.unlock()
	}
	return p.effects.remove(typ)
}

pub fn (mut p Player) tick_effects() effect.TickResult {
	p.state_mutex.lock()
	defer {
		p.state_mutex.unlock()
	}
	return p.effects.tick()
}

pub fn (p &Player) effect(typ effect.Type) ?effect.Effect {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.effects.effect(typ)
}

pub fn (p &Player) active_effects() []effect.Effect {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.effects.effects()
}

pub fn (p &Player) has_last_death() bool {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.has_last_death
}

pub fn (p &Player) last_death_pos() types.Vector3 {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.last_death_pos
}

pub fn (mut p Player) set_last_death(pos types.Vector3) {
	p.state_mutex.lock()
	p.has_last_death = true
	p.last_death_pos = pos
	p.state_mutex.unlock()
}

// Movement is a consistent snapshot of the player's position and orientation.
// Reads go through this type, while registered session writes are owned by the
// Hub thread.
pub struct Movement {
pub:
	position types.Vector3
	pitch    f32
	yaw      f32
	head_yaw f32
	vy       f32
}

pub fn (p &Player) movement() Movement {
	mut m := p.pos_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return Movement{
		position: p.position
		pitch:    p.pitch
		yaw:      p.yaw
		head_yaw: p.head_yaw
		vy:       p.vy
	}
}

// position is a convenience accessor for the common case of needing just the
// position, still going through the same lock as movement().
pub fn (p &Player) position() types.Vector3 {
	return p.movement().position
}

// apply_movement updates the player's position and orientation as one unit,
// deriving vertical velocity from the change in Y. Registered session callers
// must invoke it on the Hub thread.
pub fn (mut p Player) apply_movement(position types.Vector3, pitch f32, yaw f32, head_yaw f32) {
	p.pos_mutex.lock()
	p.vy = position.y - p.prev_y
	p.prev_y = position.y
	p.position = position
	p.pitch = pitch
	p.yaw = yaw
	p.head_yaw = head_yaw
	p.pos_mutex.unlock()
}

pub fn (mut p Player) reset_position(position types.Vector3) {
	p.pos_mutex.lock()
	p.position = position
	p.prev_y = position.y
	p.vy = 0.0
	p.pos_mutex.unlock()
}

// set_orientation applies saved orientation during pre registration setup.
// Live sessions must update orientation through apply_movement instead.
pub fn (mut p Player) set_orientation(pitch f32, yaw f32, head_yaw f32) {
	p.pos_mutex.lock()
	p.pitch = pitch
	p.yaw = yaw
	p.head_yaw = head_yaw
	p.pos_mutex.unlock()
}
