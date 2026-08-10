module entity

import rand
import server.types

const item_gravity = f32(0.04)
const item_drag = f32(0.02)

pub const item_pickup_delay_ticks = i64(10)

pub const item_drop_pickup_delay_ticks = i64(40)

pub const item_existence_duration_ticks = i64(6000)

// item_pickup_radius is how close a player must be for a ground item to
// attempt collection each tick.
const item_pickup_radius = f32(1.25)

// item_merge_radius is how close two compatible ground item stacks must be
// to combine into one.
const item_merge_radius = f32(1.0)

fn item_dimensions() Dimensions {
	return Dimensions{
		width:         0.25
		height:        0.25
		eye_height:    0.125
		step_height:   0.0
		has_collision: true
	}
}

// ItemBehaviour represents a dropped item stack. It falls, becomes
// collectible and mergeable after its pickup delay, and despawns when its
// lifetime expires.
@[heap]
pub struct ItemBehaviour {
pub mut:
	stack              types.ItemStack
	max_stack_size     int = 64
	pickup_delay_ticks i64 = item_pickup_delay_ticks
}

pub fn new_item_behaviour(stack types.ItemStack, max_stack_size int, pickup_delay_ticks i64) &ItemBehaviour {
	return &ItemBehaviour{
		stack:              stack
		max_stack_size:     max_stack_size
		pickup_delay_ticks: pickup_delay_ticks
	}
}

pub fn (b &ItemBehaviour) identifier() string {
	return 'minecraft:item'
}

pub fn (b &ItemBehaviour) dimensions() Dimensions {
	return item_dimensions()
}

pub fn (b &ItemBehaviour) despawn_policy() DespawnPolicy {
	return DespawnPolicy{}
}

pub fn (b &ItemBehaviour) takes_fall_damage() bool {
	return false
}

pub fn (mut b ItemBehaviour) tick(mut e Entity, mut host Host) {
	e.gravity_accel = item_gravity
	e.drag_factor = item_drag

	if b.stack.count <= 0 {
		e.kill()
		return
	}
	if e.age >= item_existence_duration_ticks {
		e.kill()
		return
	}
	if e.age < b.pickup_delay_ticks {
		return
	}
	target_rid := host.nearest_player(e.pos, item_pickup_radius) or { return }
	collected := host.collect_item(target_rid, b.stack)
	if collected <= 0 {
		return
	}
	host.notify_item_taken(e.runtime_id, target_rid)
	b.stack.count -= collected
	if b.stack.count <= 0 {
		e.kill()
	}
}

// Mergeable allows an entity to combine with another compatible entity.
// merge_stack provides the stack to compare and update while mergeable_now
// prevents merging until the entity's pickup delay has elapsed.
pub interface Mergeable {
	merge_radius() f32
	merge_stack() types.ItemStack
	stack_room() int
	mergeable_now(age i64) bool
mut:
	add_count(n int)
}

pub fn (b &ItemBehaviour) merge_radius() f32 {
	return item_merge_radius
}

pub fn (b &ItemBehaviour) merge_stack() types.ItemStack {
	return b.stack
}

pub fn (b &ItemBehaviour) stack_room() int {
	return b.max_stack_size - b.stack.count
}

pub fn (b &ItemBehaviour) mergeable_now(age i64) bool {
	return age >= b.pickup_delay_ticks
}

pub fn (mut b ItemBehaviour) add_count(n int) {
	b.stack.count += n
}

// rand_int_range returns a random value between min and max, inclusive.
// If max is not greater than min, it returns min.
pub fn rand_int_range(min int, max int) int {
	if max <= min {
		return min
	}
	return min + (rand.intn(max - min + 1) or { 0 })
}
