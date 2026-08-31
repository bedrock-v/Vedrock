module entity

import bedrock_v.protocol
import bedrock_v.protocol.types
import server.world
import server.effect
import bedrock_v.protocol.current as proto

// gravity and drag are applied per tick to any entity that is not marked
// no_gravity. Values are in blocks/tick, matching Bedrock's ~0.08 gravity and
// light air drag.
const gravity = f32(0.08)
const drag = f32(0.02)

const mob_max_health = f32(20.0)

const fall_damage_safe_distance = f32(3.0)

// Entity is a non-player actor living in the world - a mob, item or projectile.
// It owns shared state and delegates per-tick logic to its Behaviour. Players
// stay as NetworkSession; this system covers everything else the client renders
// as an actor.
@[heap]
pub struct Entity {
pub:
	unique_id  i64
	runtime_id u64
	identifier string     // network type id, e.g. "minecraft:pig"
	dimensions Dimensions // physical footprint, fixed at spawn from the Behaviour that created this entity
pub mut:
	pos       types.Vector3
	velocity  types.Vector3
	pitch     f32
	yaw       f32
	head_yaw  f32
	floor_y   f32
	on_ground bool
	// fall_distance accumulates actual downward movement while airborne and
	// resets on landing - see apply_landing/fall_damage_amount below.
	fall_distance f32
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
	host.broadcast(&proto.ActorEventPacket{
		target_runtime_id: proto.actor_runtime_id(e.runtime_id)
		event_id:          proto.ActorEvent.hurt
		data:              0
	})
	host.broadcast(e.health_update_packet())
	if e.health <= 0 {
		e.kill()
		if mut e.behaviour is DeathBehaviour {
			e.behaviour.on_death(mut e, mut host)
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

// apply_physics integrates velocity into position, applying gravity and
// drag, then resolves collision against the solid blocks around the
// entity's box using the Host's block query. Called by the Manager after
// the Behaviour ticks.
//
// Collision resolution clamps movement against nearby block boxes. It
// gathers the swept region once, then resolves movement along Y, X and Z
// by shrinking each offset to the largest non-penetrating value.
//
// floor_y remains a final safety floor for ungenerated terrain, independent
// of block collision and dimensions.has_collision.
//
// An entity with dimensions.has_collision == false skips block collision
// entirely and simply falls/moves through blocks.
fn (mut e Entity) apply_physics(mut host Host) {
	if !e.no_gravity {
		e.velocity.y -= e.gravity_accel
	}
	e.velocity.x *= (1.0 - e.drag_factor)
	e.velocity.y *= (1.0 - e.drag_factor)
	e.velocity.z *= (1.0 - e.drag_factor)

	e.hit_block = false

	if !e.dimensions.has_collision {
		e.pos.x += e.velocity.x
		e.pos.z += e.velocity.z
		e.on_ground = false
		y_before := e.pos.y
		e.pos.y += e.velocity.y
		if e.pos.y <= e.floor_y {
			e.pos.y = e.floor_y
			e.velocity.y = 0.0
			e.on_ground = true
		}
		if y_before > e.pos.y {
			e.fall_distance += y_before - e.pos.y
		}
		if e.on_ground {
			e.apply_landing(mut host)
		}
		return
	}

	want_dx := e.velocity.x
	want_dy := e.velocity.y
	want_dz := e.velocity.z

	boxes := e.nearby_block_boxes(mut host, want_dx, want_dy, want_dz)
	mut resolved_dx, mut resolved_dy, mut resolved_dz := e.resolve_move(boxes, want_dx, want_dy,
		want_dz)

	can_step := e.dimensions.step_height > 0 && (e.on_ground || want_dy <= 0)
	mut stepped := false
	if can_step && (resolved_dx != want_dx || resolved_dz != want_dz) {
		step_dx, step_dy, step_dz := e.try_step_up(boxes, want_dx, want_dz)
		if (step_dx * step_dx + step_dz * step_dz) > (resolved_dx * resolved_dx +
			resolved_dz * resolved_dz) {
			resolved_dx = step_dx
			resolved_dy = step_dy
			resolved_dz = step_dz
			stepped = true
		}
	}

	y_before := e.pos.y
	e.pos.x += resolved_dx
	e.pos.y += resolved_dy
	e.pos.z += resolved_dz

	if resolved_dx != want_dx {
		e.velocity.x = 0.0
		e.hit_block = true
	}
	if resolved_dz != want_dz {
		e.velocity.z = 0.0
		e.hit_block = true
	}

	e.on_ground = false
	if stepped {
		e.velocity.y = 0.0
		e.on_ground = true
		e.hit_block = true
	} else if resolved_dy != want_dy {
		e.velocity.y = 0.0
		e.hit_block = true
		if want_dy < 0 {
			e.on_ground = true
		}
	}

	if e.pos.y <= e.floor_y {
		e.pos.y = e.floor_y
		e.velocity.y = 0.0
		e.on_ground = true
	}

	if y_before > e.pos.y {
		e.fall_distance += y_before - e.pos.y
	}
	if e.on_ground {
		e.apply_landing(mut host)
	}
}

// nearby_block_boxes returns the block collision boxes intersecting the
// entity's swept movement region. The result is gathered once and reused
// while resolving movement along each axis.
fn (e &Entity) nearby_block_boxes(mut host Host, dx f32, dy f32, dz f32) []world.AABB {
	half_width := e.dimensions.width / 2
	height := e.dimensions.height

	min_dx := if dx < 0 { dx } else { f32(0) }
	max_dx := if dx > 0 { dx } else { f32(0) }
	min_dy := if dy < 0 { dy } else { f32(0) }
	max_dy := if dy > 0 { dy } else { f32(0) }
	min_dz := if dz < 0 { dz } else { f32(0) }
	max_dz := if dz > 0 { dz } else { f32(0) }

	bx0 := int(math_floor(e.pos.x - half_width + min_dx))
	bx1 := int(math_floor(e.pos.x + half_width + max_dx))
	by0 := int(math_floor(e.pos.y + min_dy))
	by1 := int(math_floor(e.pos.y + height + max_dy))
	bz0 := int(math_floor(e.pos.z - half_width + min_dz))
	bz1 := int(math_floor(e.pos.z + half_width + max_dz))

	mut out := []world.AABB{}
	for bx := bx0; bx <= bx1; bx++ {
		for by := by0; by <= by1; by++ {
			for bz := bz0; bz <= bz1; bz++ {
				for block_box in host.collision_boxes(bx, by, bz) {
					out << block_box
				}
			}
		}
	}
	return out
}

// entity_box returns the entity's current collision box.
fn (e &Entity) entity_box() world.AABB {
	half_width := e.dimensions.width / 2
	height := e.dimensions.height
	return world.box(e.pos.x - half_width, e.pos.y, e.pos.z - half_width, e.pos.x + half_width,

		e.pos.y + height, e.pos.z + half_width)
}

// resolve_move clamps the requested movement against nearby collision boxes.
// It resolves Y, then X, then Z, translating the box after each axis so the
// next axis is checked from the position already reached.
fn (e &Entity) resolve_move(boxes []world.AABB, dx f32, dy f32, dz f32) (f32, f32, f32) {
	mut box := e.entity_box()

	mut resolved_dy := dy
	for b in boxes {
		resolved_dy = box.offset_y(b, resolved_dy)
	}
	box = box.offset_by(0, resolved_dy, 0)

	mut resolved_dx := dx
	for b in boxes {
		resolved_dx = box.offset_x(b, resolved_dx)
	}
	box = box.offset_by(resolved_dx, 0, 0)

	mut resolved_dz := dz
	for b in boxes {
		resolved_dz = box.offset_z(b, resolved_dz)
	}

	return resolved_dx, resolved_dy, resolved_dz
}

fn (e &Entity) try_step_up(boxes []world.AABB, want_dx f32, want_dz f32) (f32, f32, f32) {
	mut box := e.entity_box()

	mut step_dy := e.dimensions.step_height
	for b in boxes {
		step_dy = box.offset_y(b, step_dy)
	}
	box = box.offset_by(0, step_dy, 0)

	mut step_dx := want_dx
	for b in boxes {
		step_dx = box.offset_x(b, step_dx)
	}
	box = box.offset_by(step_dx, 0, 0)

	mut step_dz := want_dz
	for b in boxes {
		step_dz = box.offset_z(b, step_dz)
	}
	box = box.offset_by(0, 0, step_dz)

	mut settle := -step_dy
	for b in boxes {
		settle = box.offset_y(b, settle)
	}
	step_dy += settle

	return step_dx, step_dy, step_dz
}

fn (mut e Entity) apply_landing(mut host Host) {
	if e.fall_distance > 0 {
		dmg := fall_damage_amount(e.fall_distance)
		if dmg > 0 && e.behaviour.takes_fall_damage() {
			e.hurt(mut host, dmg, true, 0)
		}
	}
	e.fall_distance = 0
}

fn fall_damage_amount(fall_distance f32) f32 {
	over := fall_distance - fall_damage_safe_distance
	if over <= 0 {
		return 0
	}
	whole := f32(int(over))
	if over > whole {
		return whole + 1
	}
	return whole
}

// math_floor is an integer floor that also handles negative coordinates, where a
// plain int() cast truncates toward zero and would misplace the block cell.
fn math_floor(v f32) f32 {
	i := f32(int(v))
	return if v < i { i - 1.0 } else { i }
}

// spawn_packet builds the packet that makes this entity appear for a
// viewer. Public so the session layer can send it to players joining late.
pub fn (e &Entity) spawn_packet() protocol.Packet {
	if e.behaviour is ItemBehaviour {
		item_stack := e.behaviour.stack
		mut packet := &proto.AddItemActorPacket{
			target_actor_id:   proto.actor_unique_id(e.unique_id)
			target_runtime_id: proto.actor_runtime_id(e.runtime_id)
			item:              proto.item_descriptor(item_stack)
			entity_data:       e.metadata_entries()
			from_fishing:      false
		}
		packet.position[0] = e.pos.x
		packet.position[1] = e.pos.y
		packet.position[2] = e.pos.z
		packet.velocity[0] = e.velocity.x
		packet.velocity[1] = e.velocity.y
		packet.velocity[2] = e.velocity.z
		return packet
	}
	mut packet := &proto.AddActorPacket{
		target_actor_id:   proto.actor_unique_id(e.unique_id)
		target_runtime_id: proto.actor_runtime_id(e.runtime_id)
		actor_type:        e.identifier
		y_head_rotation:   e.head_yaw
		y_body_rotation:   e.yaw
		attributes:        e.attribute_entries()
		actor_data:        e.metadata_entries()
		synced_properties: proto.PropertySyncData{}
		actor_links:       []proto.ActorLink{}
	}
	packet.position[0] = e.pos.x
	packet.position[1] = e.pos.y
	packet.position[2] = e.pos.z
	packet.velocity[0] = e.velocity.x
	packet.velocity[1] = e.velocity.y
	packet.velocity[2] = e.velocity.z
	packet.rotation[0] = e.pitch
	packet.rotation[1] = e.yaw
	return packet
}

// attribute_entries builds the health attribute the client needs at spawn
// time.
fn (e &Entity) attribute_entries() proto.AttributeEntries {
	return [
		proto.AttributeEntry{
			attribute_name: 'minecraft:health'
			min_value:      0.0
			current_value:  e.health
			max_value:      mob_max_health
		},
	]
}

// health_update_packet reports the current health attribute to observers.
// Used whenever health changes after spawn (hurt/heal) so a client watching
// this entity's health bar actually sees the new value.
fn (e &Entity) health_update_packet() &proto.UpdateAttributesPacket {
	return &proto.UpdateAttributesPacket{
		target_runtime_id:       proto.actor_runtime_id(e.runtime_id)
		attribute_list:          [
			proto.AttributeData{
				min_value:           0.0
				max_value:           mob_max_health
				current_value:       e.health
				default_min:         0.0
				default_max:         mob_max_health
				default_value:       mob_max_health
				attribute_name:      'minecraft:health'
				attribute_modifiers: []proto.AttributeModifier{}
			},
		]
		ticks_since_sim_started: 0
	}
}

// entity_flag_bit computes the metadata flag bitmask contribution for the
// flag at index.
fn entity_flag_bit(index int) i64 {
	return i64(u64(1) << u64(index))
}

fn (e &Entity) metadata_entries() []proto.DataItem {
	mut flags := i64(0)
	if e.dimensions.has_collision {
		flags |= entity_flag_bit(proto.entity_flag_has_collision)
	}
	if !e.no_gravity {
		flags |= entity_flag_bit(proto.entity_flag_affected_by_gravity)
	}
	return [
		proto.DataItem{
			data_item_id:   proto.meta_key_flags
			data_item_type: proto.DataItemInt64{
				value: flags
			}
		},
		proto.DataItem{
			data_item_id:   proto.meta_key_scale
			data_item_type: proto.DataItemFloat{
				value: f32(1.0)
			}
		},
		proto.DataItem{
			data_item_id:   proto.meta_key_width
			data_item_type: proto.DataItemFloat{
				value: e.dimensions.width
			}
		},
		proto.DataItem{
			data_item_id:   proto.meta_key_height
			data_item_type: proto.DataItemFloat{
				value: e.dimensions.height
			}
		},
	]
}

// move_packet builds the movement update broadcast each tick the entity moves.
pub fn (e &Entity) move_packet() &proto.MoveActorAbsolutePacket {
	mut flags := 0
	if e.on_ground {
		flags = proto.move_actor_flag_on_ground
	}
	return &proto.MoveActorAbsolutePacket{
		move_data: proto.MoveActorAbsoluteData{
			actor_runtime_id: proto.actor_runtime_id(e.runtime_id)
			header:           i8(flags)
			position_x:       e.pos.x
			position_y:       e.pos.y
			position_z:       e.pos.z
			rotation_x:       proto.rotation_byte(e.pitch)
			rotation_y:       proto.rotation_byte(e.yaw)
			rotation_y_head:  proto.rotation_byte(e.head_yaw)
		}
	}
}

// despawn_packet builds the RemoveActorPacket that removes this entity from a
// viewer.
pub fn (e &Entity) despawn_packet() &proto.RemoveActorPacket {
	return &proto.RemoveActorPacket{
		target_actor_id: proto.actor_unique_id(e.unique_id)
	}
}
