module entity

import math
import rand
import types

// Behaviour drives an Entity's per-tick logic, mirroring dragonfly's Behaviour
// interface. identifier() returns the network type id used when the entity is
// spawned for clients; tick() runs once per server tick before physics is
// applied, with Host access for querying/affecting the rest of the world. A
// Behaviour mutates the Entity directly (velocity, kill, etc.).
pub interface Behaviour {
	identifier() string
	dimensions() Dimensions
	// despawn_policy defines which distance based despawn rules apply to this
	// entity. The zero value disables them all and is valid for persistent
	// entities or those that manage their own lifetime.
	despawn_policy() DespawnPolicy
	takes_fall_damage() bool
mut:
	tick(mut e Entity, mut host Host)
}

// HurtBehaviour is an opt-in capability: a Behaviour implementing it is
// notified whenever its Entity survives a hit, letting e.g. a hostile mob
// start targeting whoever hit it.
pub interface HurtBehaviour {
mut:
	on_hurt(mut e Entity, amount f32, source_runtime_id u64)
}

// DeathBehaviour is an opt-in capability notified once, right before an
// Entity that died from Entity.hurt is despawned , as opposed to
// Behaviour.tick calling kill() directly for other reasons (a projectile
// expiring, a wandering mob walking into the void). host is passed through
// so a mob can drop loot without the entity package needing to know
// numeric item ids itself (see Host.spawn_dropped_item).
pub interface DeathBehaviour {
mut:
	on_death(mut e Entity, mut host Host)
}

// MobLootEntry is one line of a mob's death drop table.
struct MobLootEntry {
	item_name string
	min_count int
	max_count int
}

fn mob_loot_drops(network_id string) []MobLootEntry {
	if network_id == 'minecraft:pig' {
		return [MobLootEntry{'minecraft:porkchop', 1, 3}]
	}
	if network_id == 'minecraft:cow' {
		mut drops := []MobLootEntry{}
		drops << MobLootEntry{'minecraft:beef', 1, 3}
		drops << MobLootEntry{'minecraft:leather', 0, 2}
		return drops
	}
	if network_id == 'minecraft:chicken' {
		mut drops := []MobLootEntry{}
		drops << MobLootEntry{'minecraft:chicken', 1, 1}
		drops << MobLootEntry{'minecraft:feather', 0, 2}
		return drops
	}
	if network_id == 'minecraft:zombie' {
		return [MobLootEntry{'minecraft:rotten_flesh', 0, 2}]
	}
	return []MobLootEntry{}
}

fn apply_mob_loot_drops(network_id string, e &Entity, mut host Host) {
	for entry in mob_loot_drops(network_id) {
		count := rand_int_range(entry.min_count, entry.max_count)
		if count > 0 {
			host.spawn_dropped_item(entry.item_name, count, e.pos)
		}
	}
}

const wander_interval_ticks = i64(100)
const wander_speed = f32(0.08)
const hostile_speed = f32(0.14)
// detection_scan_interval_ticks bounds how often an untargeted HostileBehaviour
// queries the Host for the nearest player, instead of every tick.
const detection_scan_interval_ticks = i64(10)
// give_up_range_multiplier is how much farther than detection_radius a target
// must drift before a HostileBehaviour drops it, wider than the detect range
// so a target sitting right at the boundary doesn't flip flop every scan.
const give_up_range_multiplier = f32(1.5)
// path_recompute_interval_ticks bounds how often a chasing HostileBehaviour
// re-runs find_path, instead of every tick - a moving target makes any path
// stale quickly anyway, so recomputing more often than this buys little.
const path_recompute_interval_ticks = i64(20)
// path_waypoint_reached_distance is how close (blocks, horizontal) counts as
// having arrived at the current waypoint, advancing to the next.
const path_waypoint_reached_distance = f32(0.3)

// set_wander_velocity picks a new random horizontal direction and walk speed.
fn set_wander_velocity(mut e Entity, speed f32) {
	angle := rand.f32_in_range(0, f32(2.0 * math.pi)) or { 0 }
	e.velocity.x = math.cosf(angle) * speed
	e.velocity.z = math.sinf(angle) * speed
	e.yaw = angle * (180.0 / f32(math.pi))
	e.head_yaw = e.yaw
}

// PassiveBehaviour wanders in a new random direction roughly every
// wander_interval_ticks while grounded and otherwise does nothing.
// Physics still applies, so the entity falls to floor_y and
// rests there between wanders.
@[heap]
pub struct PassiveBehaviour {
pub mut:
	network_id     string
	dimensions     Dimensions
	despawn_policy DespawnPolicy
mut:
	wander_cooldown i64 = wander_interval_ticks
}

pub fn (b &PassiveBehaviour) identifier() string {
	return b.network_id
}

pub fn (b &PassiveBehaviour) dimensions() Dimensions {
	return b.dimensions
}

pub fn (b &PassiveBehaviour) despawn_policy() DespawnPolicy {
	return b.despawn_policy
}

pub fn (b &PassiveBehaviour) takes_fall_damage() bool {
	return true
}

// on_death drops this mob's loot table (see mob_loot_drops) at its death
// position.
pub fn (mut b PassiveBehaviour) on_death(mut e Entity, mut host Host) {
	apply_mob_loot_drops(b.network_id, e, mut host)
}

pub fn (mut b PassiveBehaviour) tick(mut e Entity, mut host Host) {
	if !e.on_ground {
		return
	}
	b.wander_cooldown--
	if b.wander_cooldown > 0 {
		return
	}
	b.wander_cooldown = wander_interval_ticks
	set_wander_velocity(mut e, wander_speed)
}

// HostileBehaviour wanders the same way PassiveBehaviour does until it either
// gets hurt (reactive) or spots a player within detection_radius on its own
// (proactive), then chases that runtime id directly until the target dies,
// despawns or wanders far enough past detection_radius to give up. However there is no line of sight or sound based
// detection, just a periodic radius scan.
@[heap]
pub struct HostileBehaviour {
pub mut:
	network_id       string
	detection_radius f32 = 16.0
	dimensions       Dimensions
	despawn_policy   DespawnPolicy
mut:
	wander_cooldown   i64 = wander_interval_ticks
	scan_cooldown     i64
	target_runtime_id u64
	has_target        bool
	path                    []types.Vector3
	path_index              int
	path_recompute_cooldown i64
}

pub fn (b &HostileBehaviour) identifier() string {
	return b.network_id
}

pub fn (b &HostileBehaviour) dimensions() Dimensions {
	return b.dimensions
}

pub fn (b &HostileBehaviour) despawn_policy() DespawnPolicy {
	return b.despawn_policy
}

pub fn (b &HostileBehaviour) takes_fall_damage() bool {
	return true
}

pub fn (mut b HostileBehaviour) tick(mut e Entity, mut host Host) {
	if b.has_target {
		if target_pos := host.entity_position(b.target_runtime_id) {
			dx := target_pos.x - e.pos.x
			dz := target_pos.z - e.pos.z
			dist := math.sqrtf(dx * dx + dz * dz)
			if dist > b.detection_radius * give_up_range_multiplier {
				b.has_target = false
				b.path = []
			} else {
				b.move_toward_target(mut e, mut host, target_pos)
				return
			}
		} else {
			// target no longer exists (died, despawned); go back to wandering.
			b.has_target = false
			b.path = []
		}
	}
	b.scan_cooldown--
	if b.scan_cooldown <= 0 {
		b.scan_cooldown = detection_scan_interval_ticks
		if target_runtime_id := host.nearest_player(e.pos, b.detection_radius) {
			b.acquire_target(target_runtime_id)
			return
		}
	}
	if !e.on_ground {
		return
	}
	b.wander_cooldown--
	if b.wander_cooldown > 0 {
		return
	}
	b.wander_cooldown = wander_interval_ticks
	set_wander_velocity(mut e, wander_speed)
}

fn (mut b HostileBehaviour) acquire_target(target_runtime_id u64) {
	b.has_target = true
	b.target_runtime_id = target_runtime_id
	b.path = []
	b.path_index = 0
	b.path_recompute_cooldown = 0
}

fn (mut b HostileBehaviour) move_toward_target(mut e Entity, mut host Host, target_pos types.Vector3) {
	b.path_recompute_cooldown--
	if b.path.len == 0 || b.path_index >= b.path.len || b.path_recompute_cooldown <= 0 {
		b.path_recompute_cooldown = path_recompute_interval_ticks
		b.path_index = 0
		if path := find_path(mut host, e.pos, target_pos, e.dimensions) {
			b.path = path
		} else {
			b.path = []
		}
	}

	mut waypoint := target_pos
	if b.path_index < b.path.len {
		waypoint = b.path[b.path_index]
		wdx := waypoint.x - e.pos.x
		wdz := waypoint.z - e.pos.z
		if math.sqrtf(wdx * wdx + wdz * wdz) < path_waypoint_reached_distance {
			b.path_index++
			waypoint = if b.path_index < b.path.len { b.path[b.path_index] } else { target_pos }
		}
	}

	dx := waypoint.x - e.pos.x
	dz := waypoint.z - e.pos.z
	dist := math.sqrtf(dx * dx + dz * dz)
	if dist > 0.2 {
		e.velocity.x = (dx / dist) * hostile_speed
		e.velocity.z = (dz / dist) * hostile_speed
		e.yaw = f32(math.atan2(f64(dz), f64(dx)) * (180.0 / math.pi))
		e.head_yaw = e.yaw
	}
}

// on_hurt makes the mob start chasing whoever/whatever just hit it. Plain
// PassiveBehaviour mobs don't implement HurtBehaviour, so being attacked
// never gives them a target.
pub fn (mut b HostileBehaviour) on_hurt(mut e Entity, amount f32, source_runtime_id u64) {
	if source_runtime_id == 0 {
		return
	}
	b.acquire_target(source_runtime_id)
}

// on_death drops this mob's loot table (see mob_loot_drops) at its death
// position.
pub fn (mut b HostileBehaviour) on_death(mut e Entity, mut host Host) {
	apply_mob_loot_drops(b.network_id, e, mut host)
}

// ProjectileBehaviour flies with its initial velocity, deals damage to the
// first entity or player its path touches and either despawns on its first
// block collision (survive_block_collision: false, e.g. a snowball) or freezes
// in place there until max_age (survive_block_collision: true, e.g. an arrow).
@[heap]
pub struct ProjectileBehaviour {
pub mut:
	network_id              string
	max_age                 i64 = 100
	damage                  f32
	gravity_accel           f32 = gravity
	drag_factor             f32 = drag
	survive_block_collision bool
	dimensions              Dimensions
	flying_despawn_policy   DespawnPolicy = DespawnPolicy{
		distance:      true
		random_chance: true
	}
mut:
	stuck     bool
	stuck_age i64
}

pub fn (b &ProjectileBehaviour) identifier() string {
	return b.network_id
}

pub fn (b &ProjectileBehaviour) dimensions() Dimensions {
	return b.dimensions
}

// despawn_policy changes with projectile state. While flying, the
// configured distance policy applies because no other lifetime rule can
// remove a projectile that never lands. Since this engine doesn't cull
// entities when chunks unload, distance despawning fills that role.
//
// Once stuck, distance despawning is disabled and stuck_age/max_age becomes
// the sole authority for removal. This is intentionally not configurable
// per instance, preventing distance rules from interfering with the stuck
// projectile lifetime.
pub fn (b &ProjectileBehaviour) despawn_policy() DespawnPolicy {
	if b.stuck {
		return DespawnPolicy{}
	}
	return b.flying_despawn_policy
}

pub fn (b &ProjectileBehaviour) takes_fall_damage() bool {
	return false
}

pub fn (mut b ProjectileBehaviour) tick(mut e Entity, mut host Host) {
	if b.stuck {
		b.stuck_age++
		if b.stuck_age >= b.max_age {
			e.kill()
		}
		return
	}
	e.gravity_accel = b.gravity_accel
	e.drag_factor = b.drag_factor
	if e.age <= 1 {
		return
	}
	if hit_runtime_id := host.entity_hit_test(e.pos, e.runtime_id) {
		host.damage_entity(hit_runtime_id, b.damage, e.identifier, e.runtime_id, e.pos)
		e.kill()
		return
	}
	if e.hit_block {
		if b.survive_block_collision {
			// Freeze in place rather than despawn. no_gravity plus a zeroed
			// velocity makes apply_physics a noop from here on, same effect
			// as skipping physics for this entity without special casing it
			// in Manager.tick.
			b.stuck = true
			e.no_gravity = true
			e.velocity = types.Vector3{}
			return
		}
		// hit_block is a superset of on_ground (it also covers hitting a wall
		// or ceiling), so a nonsurviving projectile now despawns on any axis
		// collision, not just landing on top.
		e.kill()
	}
}
