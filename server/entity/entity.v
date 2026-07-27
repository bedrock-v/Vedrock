module entity

import protocol
import protocol.types
import server.world
import server.effect

// gravity and drag are applied per tick to any entity that is not marked
// no_gravity. Values are in blocks/tick, matching Bedrock's ~0.08 gravity and
// light air drag.
const gravity = f32(0.08)
const drag = f32(0.02)

const mob_max_health = f32(20.0)

// Entity is a non-player actor living in the world - a mob, item or projectile.
// It is the Vedrock counterpart to dragonfly's Ent: shared state plus a pluggable
// Behaviour that drives its per-tick logic. Players stay as NetworkSession; this
// system covers everything else the client renders as an actor.
@[heap]
pub struct Entity {
pub:
	unique_id  i64
	runtime_id u64
	identifier string     // network type id, e.g. "minecraft:pig"
	dimensions Dimensions // physical footprint, fixed at spawn from the Behaviour that created this entity
pub mut:
	pos           types.Vector3
	velocity      types.Vector3
	pitch         f32
	yaw           f32
	head_yaw      f32
	floor_y       f32
	on_ground     bool
	no_gravity    bool
	gravity_accel f32 = gravity
	drag_factor   f32 = drag
	hit_block     bool
	health        f32 = 20.0
	dead          bool
	age           i64
	// ticks_inactive counts ticks since this entity was last hurt.
	ticks_inactive i64
	behaviour      Behaviour
	effects        effect.Manager
}

// current_position returns the entity's current position.
pub fn (e &Entity) current_position() types.Vector3 {
	return e.pos
}

// feet_position satisfies entity.Actor. An Entity's pos is already its feet
// , so this is the same value as current_position().
pub fn (e &Entity) feet_position() types.Vector3 {
	return e.pos
}

// dimensions satisfies entity.Actor.
pub fn (e &Entity) dimensions() Dimensions {
	return e.dimensions
}

// runtime_id satisfies entity.Actor.
pub fn (e &Entity) runtime_id() u64 {
	return e.runtime_id
}

// is_dead reports whether the entity is scheduled for removal.
pub fn (e &Entity) is_dead() bool {
	return e.dead
}

// kill marks the entity dead. The Manager removes and despawns it on the next
// tick.
pub fn (mut e Entity) kill() {
	e.dead = true
}

// set_velocity replaces the entity's velocity (blocks/tick).
pub fn (mut e Entity) set_velocity(v types.Vector3) {
	e.velocity = v
}

pub fn (mut e Entity) hurt(mut host Host, amount f32, fatal bool, source_runtime_id u64) {
	if e.dead || amount <= 0 {
		return
	}
	e.ticks_inactive = 0
	if !fatal && e.health - amount < 1 {
		e.health = 1
	} else {
		e.health -= amount
	}
	if e.health < 0 {
		e.health = 0
	}
	host.broadcast(&protocol.ActorEventPacket{
		actor_runtime_id: e.runtime_id
		event_id:         protocol.actor_event_hurt
		event_data:       0
	})
	host.broadcast(e.health_update_packet())
	if e.health <= 0 {
		e.kill()
		if mut e.behaviour is DeathBehaviour {
			e.behaviour.on_death(mut e)
		}
		return
	}
	if mut e.behaviour is HurtBehaviour {
		e.behaviour.on_hurt(mut e, amount, source_runtime_id)
	}
}

pub fn (mut e Entity) heal(mut host Host, amount f32) {
	if e.dead || amount <= 0 {
		return
	}
	e.health += amount
	if e.health > mob_max_health {
		e.health = mob_max_health
	}
	host.broadcast(e.health_update_packet())
}

// teleport moves the entity to pos and resets its ground clamp there.
pub fn (mut e Entity) teleport(pos types.Vector3) {
	e.pos = pos
	e.floor_y = pos.y
}

// apply_physics integrates velocity into position, applying gravity and drag,
// then resolves collision against the solid blocks around the entity's box using
// the Host's block query. Called by the Manager after the Behaviour ticks.
//
// Collision is axis-separated AABB vs the block grid: each axis moves
// independently and a move that would enter a solid block is cancelled and its
// velocity zeroed. Landing on a block below sets on_ground and snaps the feet to
// the block top. floor_y stays as a hard fallback floor for entities spawned
// over ungenerated terrain. It applies regardless of dimensions.has_collision,
// since it's a safety net against falling out of the world.
//
// An entity with dimensions.has_collision == false skips block collision
// entirely on every axis and simply falls/moves through blocks.
fn (mut e Entity) apply_physics(mut host Host) {
	if !e.no_gravity {
		e.velocity.y -= e.gravity_accel
	}
	e.velocity.x *= (1.0 - e.drag_factor)
	e.velocity.y *= (1.0 - e.drag_factor)
	e.velocity.z *= (1.0 - e.drag_factor)

	e.hit_block = false

	e.pos.x += e.velocity.x
	if e.dimensions.has_collision && e.collides(mut host) {
		e.pos.x -= e.velocity.x
		e.velocity.x = 0.0
		e.hit_block = true
	}

	e.pos.z += e.velocity.z
	if e.dimensions.has_collision && e.collides(mut host) {
		e.pos.z -= e.velocity.z
		e.velocity.z = 0.0
		e.hit_block = true
	}

	e.on_ground = false
	e.pos.y += e.velocity.y
	if e.dimensions.has_collision && e.collides(mut host) {
		if e.velocity.y <= 0.0 {
			// landed - snap feet to the top of the block underneath
			e.pos.y = math_floor(e.pos.y) + 1.0
			e.on_ground = true
		} else {
			// hit a ceiling - undo the upward move
			e.pos.y -= e.velocity.y
		}
		e.velocity.y = 0.0
		e.hit_block = true
	}

	if e.pos.y <= e.floor_y {
		e.pos.y = e.floor_y
		e.velocity.y = 0.0
		e.on_ground = true
	}
}

// collides reports whether the entity's AABB overlaps any block collision box.
fn (e &Entity) collides(mut host Host) bool {
	half_width := e.dimensions.width / 2
	height := e.dimensions.height
	min_x := int(math_floor(e.pos.x - half_width))
	max_x := int(math_floor(e.pos.x + half_width))
	min_z := int(math_floor(e.pos.z - half_width))
	max_z := int(math_floor(e.pos.z + half_width))
	min_y := int(math_floor(e.pos.y))
	max_y := int(math_floor(e.pos.y + height))
	entity_min_x := e.pos.x - half_width
	entity_min_z := e.pos.z - half_width
	entity_max_x := e.pos.x + half_width
	entity_max_z := e.pos.z + half_width
	entity_box := world.box(entity_min_x, e.pos.y, entity_min_z, entity_max_x, e.pos.y + height,
		entity_max_z)
	for bx := min_x; bx <= max_x; bx++ {
		for bz := min_z; bz <= max_z; bz++ {
			for by := min_y; by <= max_y; by++ {
				for block_box in host.collision_boxes(bx, by, bz) {
					if entity_box.overlaps(block_box) {
						return true
					}
				}
			}
		}
	}
	return false
}

// math_floor is an integer floor that also handles negative coordinates, where a
// plain int() cast truncates toward zero and would misplace the block cell.
fn math_floor(v f32) f32 {
	i := f32(int(v))
	return if v < i { i - 1.0 } else { i }
}

// spawn_packet builds the AddActorPacket that makes this entity appear for a
// viewer. Public so the session layer can send it to players joining late.
pub fn (e &Entity) spawn_packet() &protocol.AddActorPacket {
	return &protocol.AddActorPacket{
		actor_unique_id:   e.unique_id
		actor_runtime_id:  e.runtime_id
		type:              e.identifier
		position:          e.pos
		motion:            e.velocity
		pitch:             e.pitch
		yaw:               e.yaw
		head_yaw:          e.head_yaw
		body_yaw:          e.yaw
		attributes:        e.attribute_entries()
		metadata:          e.metadata_entries()
		synced_properties: types.PropertySyncData{}
		links:             []types.EntityLink{}
	}
}

// attribute_entries builds the health attribute the client needs at spawn
// time.
fn (e &Entity) attribute_entries() []types.ActorAttribute {
	return [
		types.ActorAttribute{
			id:      'minecraft:health'
			min:     0.0
			current: e.health
			max:     mob_max_health
		},
	]
}

// health_update_packet reports the current health attribute to observers.
// Used whenever health changes after spawn (hurt/heal) so a client watching
// this entity's health bar actually sees the new value.
fn (e &Entity) health_update_packet() &protocol.UpdateAttributesPacket {
	return &protocol.UpdateAttributesPacket{
		actor_runtime_id: e.runtime_id
		entries:          [
			types.UpdateAttribute{
				id:          'minecraft:health'
				min:         0.0
				max:         mob_max_health
				current:     e.health
				default_min: 0.0
				default_max: mob_max_health
				default:     mob_max_health
				modifiers:   []types.AttributeModifier{}
			},
		]
		tick:             0
	}
}

// entity_flag_bit computes the metadata flag bitmask contribution for the
// flag at index.
fn entity_flag_bit(index int) i64 {
	return i64(u64(1) << u64(index))
}

fn (e &Entity) metadata_entries() []types.MetadataEntry {
	mut flags := i64(0)
	if e.dimensions.has_collision {
		flags |= entity_flag_bit(protocol.entity_flag_has_collision)
	}
	if !e.no_gravity {
		flags |= entity_flag_bit(protocol.entity_flag_affected_by_gravity)
	}
	return [
		types.MetadataEntry{
			key:   protocol.meta_key_flags
			value: types.MetaLong{
				value: flags
			}
		},
		types.MetadataEntry{
			key:   protocol.meta_key_width
			value: types.MetaFloat{
				value: e.dimensions.width
			}
		},
		types.MetadataEntry{
			key:   protocol.meta_key_height
			value: types.MetaFloat{
				value: e.dimensions.height
			}
		},
	]
}

// move_packet builds the movement update broadcast each tick the entity moves.
pub fn (e &Entity) move_packet() &protocol.MoveActorAbsolutePacket {
	mut flags := 0
	if e.on_ground {
		flags = protocol.move_actor_flag_on_ground
	}
	return &protocol.MoveActorAbsolutePacket{
		actor_runtime_id: e.runtime_id
		flags:            flags
		position:         e.pos
		pitch:            e.pitch
		yaw:              e.yaw
		head_yaw:         e.head_yaw
	}
}

// despawn_packet builds the RemoveActorPacket that removes this entity from a
// viewer.
pub fn (e &Entity) despawn_packet() &protocol.RemoveActorPacket {
	return &protocol.RemoveActorPacket{
		actor_unique_id: e.unique_id
	}
}
