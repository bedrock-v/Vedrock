module entity

import sync
import rand
import protocol
import server.types
import server.world
import server.effect

// view_radius is the distance in blocks within which an entity's spawn and move
// packets are sent to a player. Beyond it the client never hears about the
// entity, so idle mobs on the far side of the world cost no bandwidth.
const view_radius = f32(64.0)

// Host is the slice of the server the entity Manager needs: world scoped
// broadcasting, collision queries and the shared runtime-id allocator.
// session.WorldEntityHost satisfies it for one world.
pub interface Host {
mut:
	broadcast(p protocol.Packet)
	broadcast_near(x f32, y f32, z f32, radius f32, p protocol.Packet)
	allocate_runtime_id() u64
	get_block(x int, y int, z int) int
	collision_boxes(x int, y int, z int) []world.AABB
	// entity_position returns the current position of any live actor (player
	// or non player entity) the Host knows about or none if runtime_id no
	// longer exists. Lets a Behaviour target something outside the entity
	// Manager's own bookkeeping without the entity package
	// importing session.
	entity_position(runtime_id u64) ?types.Vector3
	// entity_hit_test returns the runtime id of the first live actor other
	// than any id in exclude_runtime_ids whose box contains pos or none.
	// Used for projectile vs entity/player collision.
	entity_hit_test(pos types.Vector3, exclude_runtime_ids []u64) ?u64
	// damage_entity applies damage to the actor at runtime_id (player or
	// entity), attributed to source_name/source_runtime_id, with
	// knockback_from as the origin used to compute knockback direction.
	damage_entity(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3)
	// mob_attack applies a hostile mob's own melee attack to the actor at
	// runtime_id, attributed to source_name/source_runtime_id the same way
	// as damage_entity.
	mob_attack(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3)
	// nearest_player returns the runtime id of the closest connected player
	// within radius of pos or none if nobody is that close. Used for
	// proactive mob targeting (HostileBehaviour scanning for a target it
	// hasn't been hit by yet).
	nearest_player(pos types.Vector3, radius f32) ?u64
	// has_line_of_sight reports whether no solid block obstructs the segment
	// between from and to. It uses sampled points rather than exact voxel
	// traversal and currently treats all blocks with collision boxes as opaque.
	has_line_of_sight(from types.Vector3, to types.Vector3) bool
	// notify_entity_despawn lets the entity package announce a despawn.
	notify_entity_despawn(identifier string, x f32, y f32, z f32)
	// spawn_dropped_item spawns count units of a registered item at pos.
	// Unknown items and non-positive counts are ignored; name to ID resolution
	// remains in the session item registry.
	spawn_dropped_item(item_name string, count int, pos types.Vector3)
	// collect_item adds as much of stack as possible to the player identified
	// by runtime_id and returns the number of units accepted. It returns 0 if
	// no live player is registered there or the inventory cannot take any.
	collect_item(runtime_id u64, stack types.ItemStack) int
	// notify_item_taken lets viewers see the pickup animation.
	notify_item_taken(item_runtime_id u64, taker_runtime_id u64)
}

// Manager stores every live actor in a world, keyed by runtime ID.
//
// The mutex protects registry membership only. Live entity pointers must
// remain on the owning world thread; cross thread callers must copy plain
// values through a world task.
@[heap]
pub struct Manager {
mut:
	mutex  &sync.Mutex = sync.new_mutex()
	actors map[u64]ActorEntry
	host   Host
}

pub fn new_manager(host Host) &Manager {
	return &Manager{
		host: host
	}
}

// spawn creates an entity driven by behaviour at pos, registers it and
// broadcasts its appearance to all viewers. Returns the live Entity.
pub fn (mut m Manager) spawn(behaviour Behaviour, pos types.Vector3) &Entity {
	rid := m.host.allocate_runtime_id()
	mut e := &Entity{
		unique_id:  i64(rid)
		runtime_id: rid
		identifier: behaviour.identifier()
		dimensions: behaviour.dimensions()
		pos:        pos
		floor_y:    pos.y
		behaviour:  behaviour
		effects:    effect.new_manager()
	}
	m.mutex.lock()
	m.actors[rid] = ActorEntry{
		actor: e
	}
	m.mutex.unlock()
	m.host.broadcast_near(e.pos.x, e.pos.y, e.pos.z, view_radius, e.spawn_packet())
	return e
}

// despawn removes the entity with runtime_id and tells viewers to drop it.
pub fn (mut m Manager) despawn(runtime_id u64) {
	m.mutex.lock()
	entry := m.actors[runtime_id] or {
		m.mutex.unlock()
		return
	}
	if entry.actor is Entity {
		e := entry.actor
		m.actors.delete(runtime_id)
		m.mutex.unlock()
		m.host.broadcast(e.despawn_packet())
		m.host.notify_entity_despawn(e.identifier, e.pos.x, e.pos.y, e.pos.z)
		return
	}
	m.mutex.unlock()
}

// by_runtime_id returns the live entity with runtime_id or none if it does
// not exist or belongs to a player.
pub fn (mut m Manager) by_runtime_id(runtime_id u64) ?&Entity {
	m.mutex.lock()
	defer {
		m.mutex.unlock()
	}
	entry := m.actors[runtime_id] or { return none }
	if entry.actor is Entity {
		return entry.actor
	}
	return none
}

pub fn (mut m Manager) damage(runtime_id u64, amount f32, fatal bool, mut host Host, source_runtime_id u64) {
	mut e := m.by_runtime_id(runtime_id) or { return }
	e.hurt(mut host, amount, fatal, source_runtime_id)
}

// count reports how many mob entities are alive.
pub fn (mut m Manager) count() int {
	mut n := 0
	for e in m.snapshot() {
		_ = e
		n++
	}
	return n
}

// snapshot returns a stable slice of live mob entity pointers, excluding
// registered players.
pub fn (mut m Manager) snapshot() []&Entity {
	m.mutex.lock()
	defer {
		m.mutex.unlock()
	}
	mut list := []&Entity{cap: m.actors.len}
	for _, entry in m.actors {
		if entry.actor is Entity {
			list << entry.actor
		}
	}
	return list
}

// register_player_actor adds or replaces a player actor entry.
pub fn (mut m Manager) register_player_actor(a Actor, runtime_id u64, epoch i64) {
	m.mutex.lock()
	m.actors[runtime_id] = ActorEntry{
		actor: a
		epoch: epoch
	}
	m.mutex.unlock()
}

// is_player_actor reports whether the runtime ID belongs to a registered
// player. PlayerMoveTask uses it without an epoch check so stale tasks can
// still resolve the session and clear movement_scheduled.
pub fn (mut m Manager) is_player_actor(runtime_id u64) bool {
	m.mutex.lock()
	defer {
		m.mutex.unlock()
	}
	entry := m.actors[runtime_id] or { return false }
	return entry.actor !is Entity
}

// deregister_player_actor removes a player actor entry.
pub fn (mut m Manager) deregister_player_actor(runtime_id u64) {
	m.mutex.lock()
	defer {
		m.mutex.unlock()
	}
	entry := m.actors[runtime_id] or { return }
	if entry.actor !is Entity {
		m.actors.delete(runtime_id)
	}
}

// player_actor_for_epoch resolves a player actor and rejects a stale or
// missing registration before any side effects occur.
pub fn (mut m Manager) player_actor_for_epoch(runtime_id u64, epoch i64) ?Actor {
	m.mutex.lock()
	defer {
		m.mutex.unlock()
	}
	entry := m.actors[runtime_id] or { return none }
	if entry.actor is Entity {
		return none
	}
	if entry.epoch != epoch {
		return none
	}
	return entry.actor
}

// player_actors returns every registered player actor.
pub fn (mut m Manager) player_actors() []Actor {
	m.mutex.lock()
	defer {
		m.mutex.unlock()
	}
	mut list := []Actor{cap: m.actors.len}
	for _, entry in m.actors {
		if entry.actor !is Entity {
			list << entry.actor
		}
	}
	return list
}

// player_actor_count reports how many players are registered.
pub fn (mut m Manager) player_actor_count() i64 {
	mut n := i64(0)
	m.mutex.lock()
	for _, entry in m.actors {
		if entry.actor !is Entity {
			n++
		}
	}
	m.mutex.unlock()
	return n
}

// actor_by_runtime_id returns the player or non-player entity registered
// under the runtime ID. Use it only when both actor kinds are valid.
pub fn (mut m Manager) actor_by_runtime_id(runtime_id u64) ?Actor {
	m.mutex.lock()
	defer {
		m.mutex.unlock()
	}
	entry := m.actors[runtime_id] or { return none }
	return entry.actor
}

// all_actors returns every registered actor, mob and player alike.
pub fn (mut m Manager) all_actors() []Actor {
	m.mutex.lock()
	defer {
		m.mutex.unlock()
	}
	mut list := []Actor{cap: m.actors.len}
	for _, entry in m.actors {
		list << entry.actor
	}
	return list
}

// should_despawn_naturally reports whether the entity should be removed
// this tick according to its Behaviour's despawn policy. Policies with
// distance despawning disabled never qualify.
//
// The policy is also disabled while the world has no registered players.
// Without this guard, every opted-in entity in an empty but still ticking
// world would be treated as beyond the maximum distance and despawn.
fn (mut m Manager) should_despawn_naturally(e &Entity) bool {
	policy := e.behaviour.despawn_policy()
	if !policy.distance {
		return false
	}
	if m.player_actor_count() == 0 {
		return false
	}
	if _ := m.host.nearest_player(e.pos, policy.min_distance) {
		return false
	}
	if _ := m.host.nearest_player(e.pos, policy.max_distance) {
		if !policy.random_chance {
			return false
		}
		if policy.inactivity && e.ticks_inactive < policy.inactivity_ticks {
			return false
		}
		return rand.f32() < f32(1.0) / f32(policy.random_chance_one_in)
	}
	return true
}

// tick advances every entity one server tick: run its Behaviour, apply physics,
// remove the dead, and broadcast movement for the ones that moved.
pub fn (mut m Manager) tick() {
	for mut e in m.snapshot() {
		// Killed between ticks via Entity.kill() - despawn here so it leaves
		// m.entities and a RemoveActorPacket goes out, same as an in-tick death.
		if e.dead {
			m.despawn(e.runtime_id)
			continue
		}
		e.age++
		e.ticks_inactive++
		if m.should_despawn_naturally(e) {
			e.kill()
			m.despawn(e.runtime_id)
			continue
		}
		before := e.pos
		e.tick_effects(mut m.host)
		if e.dead {
			m.despawn(e.runtime_id)
			continue
		}
		e.behaviour.tick(mut e, mut m.host)
		e.apply_physics(mut m.host)
		if e.dead {
			m.despawn(e.runtime_id)
			continue
		}
		if moved(before, e.pos) {
			m.host.broadcast_near(e.pos.x, e.pos.y, e.pos.z, view_radius, e.move_packet())
		}
	}
	m.merge_items()
}

// merge_items combines nearby compatible item entities whose pickup
// cooldowns have expired. Matching stacks transfer into one another until
// the receiving stack is full; emptied donors are marked dead and removed
// by normal entity cleanup.
//
// The scan compares each live item with the others. This is acceptable for
// the expected entity counts and should only be optimized if profiling
// shows it becoming a problem.
fn (mut m Manager) merge_items() {
	list := m.snapshot()
	for i := 0; i < list.len; i++ {
		mut a := list[i]
		if a.dead {
			continue
		}
		if mut a.behaviour is Mergeable {
			if !a.behaviour.mergeable_now(a.age) {
				continue
			}
			mut a_room := a.behaviour.stack_room()
			a_stack := a.behaviour.merge_stack()
			a_radius := a.behaviour.merge_radius()
			if a_room <= 0 {
				continue
			}
			for j := i + 1; j < list.len; j++ {
				if a_room <= 0 {
					break
				}
				mut b := list[j]
				if b.dead || a.dead {
					continue
				}
				if mut b.behaviour is Mergeable {
					if !b.behaviour.mergeable_now(b.age) {
						continue
					}
					bs := b.behaviour.merge_stack()
					if bs.id != a_stack.id || bs.meta != a_stack.meta
						|| bs.block_runtime_id != a_stack.block_runtime_id
						|| bs.raw_extra_data != a_stack.raw_extra_data {
						continue
					}
					dx := a.pos.x - b.pos.x
					dy := a.pos.y - b.pos.y
					dz := a.pos.z - b.pos.z
					if dx * dx + dy * dy + dz * dz > a_radius * a_radius {
						continue
					}
					moved_count := if bs.count < a_room { bs.count } else { a_room }
					if moved_count <= 0 {
						continue
					}
					a.behaviour.add_count(moved_count)
					b.behaviour.add_count(-moved_count)
					a_room -= moved_count
					if bs.count - moved_count <= 0 {
						b.kill()
					}
				}
			}
		}
	}
}

// moved reports whether two positions differ enough to be worth a broadcast.
fn moved(a types.Vector3, b types.Vector3) bool {
	eps := f32(0.0001)
	return abs_f32(a.x - b.x) > eps || abs_f32(a.y - b.y) > eps || abs_f32(a.z - b.z) > eps
}

fn abs_f32(v f32) f32 {
	return if v < 0 { -v } else { v }
}
