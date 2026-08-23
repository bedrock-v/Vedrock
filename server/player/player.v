module player

import server.internal.auth
import server.permission
import server.effect
import server.inventory
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
	inv              inventory.Inventory
	pending_creative ?types.ItemStack
	loaded_items     []playerdb.InvItem
	effects          effect.Manager
	has_last_death   bool
	last_death_pos   types.Vector3
	air_supply_ticks i64 = max_air_supply_ticks
	fire_ticks       i64
	pos_mutex        &sync.Mutex = sync.new_mutex()
	position         types.Vector3
	pitch            f32
	yaw              f32
	head_yaw         f32
	vy               f32
	prev_y           f32
	fall_distance    f32
	grounded         bool
}

// max_air_supply_ticks is the underwater breath meter's full value.
pub const max_air_supply_ticks = i64(300)

pub fn new_player() &Player {
	return &Player{
		inv:     inventory.new()
		effects: effect.new_manager()
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

pub fn (p &Player) air_supply() i64 {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.air_supply_ticks
}

pub fn (mut p Player) set_air_supply(value i64) {
	p.state_mutex.lock()
	p.air_supply_ticks = value
	p.state_mutex.unlock()
}

pub fn (p &Player) fire_ticks() i64 {
	mut m := p.state_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.fire_ticks
}

pub fn (mut p Player) set_fire_ticks(value i64) {
	p.state_mutex.lock()
	p.fire_ticks = value
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
	return p.inv.stack(net_id)
}

pub fn (mut p Player) put_stack(net_id int, stack types.ItemStack) {
	p.inv.put_stack(net_id, stack)
}

pub fn (mut p Player) delete_stack(net_id int) {
	p.inv.delete_stack(net_id)
}

pub fn (p &Player) inv_slot(slot int) ?int {
	return p.inv.slot(slot)
}

pub fn (p &Player) has_slot(slot int) bool {
	return p.inv.has_slot(slot)
}

pub fn (mut p Player) set_slot(slot int, net_id int) {
	p.inv.set_slot(slot, net_id)
}

pub fn (mut p Player) delete_slot(slot int) {
	p.inv.delete_slot(slot)
}

// snapshot_slot_stacks returns a cloned map of inventory slot to item stack.
pub fn (p &Player) snapshot_slot_stacks() map[int]types.ItemStack {
	return p.inv.snapshot_slot_stacks()
}

// track_stack assigns stack a new network ID, stores it and returns that ID.
pub fn (mut p Player) track_stack(stack types.ItemStack) int {
	return p.inv.track_stack(stack)
}

pub fn (mut p Player) clear_inventory() {
	p.inv.clear()
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

// on_ground reports the last client reported ground state, trusted like the
// rest of the movement snapshot.
pub fn (p &Player) on_ground() bool {
	mut m := p.pos_mutex
	m.lock()
	defer {
		m.unlock()
	}
	return p.grounded
}

// position is a convenience accessor for the common case of needing just the
// position, still going through the same lock as movement().
pub fn (p &Player) position() types.Vector3 {
	return p.movement().position
}

// apply_movement updates the player's position and orientation as one unit,
// deriving vertical velocity from the change in Y. Registered session callers
// must invoke it on the Hub thread.
pub fn (mut p Player) apply_movement(position types.Vector3, pitch f32, yaw f32, head_yaw f32, on_ground bool) f32 {
	p.pos_mutex.lock()
	p.vy = position.y - p.prev_y
	if p.vy < 0 {
		p.fall_distance += -p.vy
	}
	mut landed_distance := f32(0)
	if on_ground {
		landed_distance = p.fall_distance
		p.fall_distance = 0
	}
	p.grounded = on_ground
	p.prev_y = position.y
	p.position = position
	p.pitch = pitch
	p.yaw = yaw
	p.head_yaw = head_yaw
	p.pos_mutex.unlock()
	return landed_distance
}

pub fn (mut p Player) reset_position(position types.Vector3) {
	p.pos_mutex.lock()
	p.position = position
	p.prev_y = position.y
	p.vy = 0.0
	p.fall_distance = 0
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
