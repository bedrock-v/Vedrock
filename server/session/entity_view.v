module session

import math
import protocol
import protocol.types
import server.effect
import server.entity
import server.event

// broadcast_near delivers p only to players whose position is within radius of
// the point (x, y, z). Used by the entity Manager for view-distance culling so
// spawn and move packets never reach players too far away to render the entity.
// Distance is compared squared to skip the sqrt.
pub fn (mut h Hub) broadcast_near(x f32, y f32, z f32, radius f32, p protocol.Packet) {
	r2 := radius * radius
	for mut target in h.snapshot() {
		// Read the position under the target's own pos_mutex - it is written on
		// that session's thread while we read here on the actor thread.
		pos := target.current_position()
		dx := pos.x - x
		dy := pos.y - y
		dz := pos.z - z
		if dx * dx + dy * dy + dz * dz <= r2 {
			target.deliver(p)
		}
	}
}

pub fn (mut h Hub) entity_position(runtime_id u64) ?types.Vector3 {
	if mut target := h.session_by_runtime(runtime_id) {
		return target.current_position()
	}
	e := h.entities.by_runtime_id(runtime_id) or { return none }
	return e.pos
}

pub fn (mut h Hub) entity_hit_test(pos types.Vector3, exclude_runtime_id u64) ?u64 {
	if rid := h.entities.hit_test(pos, exclude_runtime_id) {
		return rid
	}
	for mut target in h.snapshot() {
		if target.runtime_id == exclude_runtime_id {
			continue
		}
		tp := target.current_position()
		feet_y := tp.y - player_eye_height
		if pos.x >= tp.x - player_half_width && pos.x <= tp.x + player_half_width
			&& pos.z >= tp.z - player_half_width && pos.z <= tp.z + player_half_width
			&& pos.y >= feet_y && pos.y <= feet_y + player_height {
			return target.runtime_id
		}
	}
	return none
}

pub fn (mut h Hub) damage_entity(runtime_id u64, amount f32, source_name string, source_runtime_id u64, knockback_from types.Vector3) {
	if mut target := h.session_by_runtime(runtime_id) {
		target.apply_knockback(knockback_from, knockback_horizontal, knockback_vertical)
		target.take_damage(amount, source_name)
		return
	}
	h.entities.damage(runtime_id, amount, true, mut h, source_runtime_id)
}

pub fn (mut h Hub) nearest_player(pos types.Vector3, radius f32) ?u64 {
	rid, _, found := h.find_nearest_player(pos, radius)
	if !found {
		return none
	}
	return rid
}

// add_effect_to applies ef to the actor at runtime_id (player or entity).
pub fn (mut h Hub) add_effect_to(runtime_id u64, ef effect.Effect) {
	if mut target := h.session_by_runtime(runtime_id) {
		target.add_effect(ef)
		return
	}
	h.entities.add_effect(runtime_id, ef)
}

// entities_near returns the runtime ids of every actor (player and non-player
// entity) whose position is within radius blocks of pos. Used by splash
// potions and other area-of-effect behaviours.
pub fn (mut h Hub) entities_near(pos types.Vector3, radius f32) []u64 {
	mut ids := []u64{}
	radius_sq := radius * radius
	for e in h.entities.snapshot() {
		if e.dead {
			continue
		}
		dx := e.pos.x - pos.x
		dy := e.pos.y - pos.y
		dz := e.pos.z - pos.z
		if dx * dx + dy * dy + dz * dz <= radius_sq {
			ids << e.runtime_id
		}
	}
	for mut target in h.snapshot() {
		tp := target.current_position()
		dx := tp.x - pos.x
		dy := tp.y - pos.y
		dz := tp.z - pos.z
		if dx * dx + dy * dy + dz * dz <= radius_sq {
			ids << target.runtime_id
		}
	}
	return ids
}

// notify_entity_despawn dispatches EntityDespawnData. Observational only,
// so cancellation isn't checked here.
pub fn (mut h Hub) notify_entity_despawn(identifier string, x f32, y f32, z f32) {
	mut ctx := event.new_context(event.EntityDespawnData{
		identifier: identifier
		x:          x
		y:          y
		z:          z
	})
	h.events.entity_despawn(mut ctx)
}

const pickup_radius = f32(1.4)
const pickup_vertical_margin = f32(0.5)

fn (mut h Hub) nearest_pickup_player(pos types.Vector3) (u64, bool) {
	mut best_rid := u64(0)
	mut best_dist := pickup_radius * pickup_radius
	mut found := false
	for mut target in h.snapshot() {
		tp := target.current_position()
		feet_y := tp.y - player_eye_height
		if pos.y < feet_y - pickup_vertical_margin
			|| pos.y > feet_y + player_height + pickup_vertical_margin {
			continue
		}
		dx := tp.x - pos.x
		dz := tp.z - pos.z
		dist := dx * dx + dz * dz
		if dist <= best_dist {
			best_dist = dist
			best_rid = target.runtime_id
			found = true
		}
	}
	return best_rid, found
}

pub fn (mut h Hub) pickup_item(item_runtime_id u64, stack types.ItemStack, pos types.Vector3) int {
	rid, found := h.nearest_pickup_player(pos)
	if !found {
		return 0
	}
	mut target := h.session_by_runtime(rid) or { return 0 }
	taken := target.apply_pickup(stack)
	if taken <= 0 {
		return 0
	}
	if taken >= stack.count {
		h.broadcast(&protocol.TakeItemActorPacket{
			item_actor_runtime_id:  item_runtime_id
			taker_actor_runtime_id: rid
		})
	}
	return taken
}

pub fn (mut h Hub) drop_item(stack types.ItemStack, x f32, y f32, z f32, vx f32, vy f32, vz f32, pickup_delay i64) {
	if stack.id == 0 || stack.count <= 0 {
		return
	}
	h.entities.spawn_item(stack, types.Vector3{x, y, z}, types.Vector3{vx, vy, vz}, pickup_delay)
}

// is_undead reports whether the actor at runtime_id is an undead mob.
// Players and non-undead entities return false.
// https://minecraft.fandom.com/fr/wiki/Mort-vivant

// spawn_behaviour creates a new entity from a behaviour at the given
// position and returns the live Entity reference.
pub fn (mut h Hub) spawn_behaviour(b entity.Behaviour, pos types.Vector3) &entity.Entity {
	return h.entities.spawn(b, pos)
}

pub fn (mut h Hub) is_undead(runtime_id u64) bool {
	if h.session_by_runtime(runtime_id) != none {
		return false
	}
	e := h.entities.by_runtime_id(runtime_id) or { return false }
	return e.identifier in undead_mobs
}

// undead_mobs is the set of Bedrock entity identifiers that invert instant
// health/damage effects (Healing harms them, Harming heals them).
// https://minecraft.fandom.com/fr/wiki/Mort-vivant
const undead_mobs = [
	'minecraft:zombie',
	'minecraft:skeleton',
	'minecraft:wither_skeleton',
	'minecraft:stray',
	'minecraft:husk',
	'minecraft:drowned',
	'minecraft:zombified_piglin',
	'minecraft:zombie_pigman',
	'minecraft:zoglin',
	'minecraft:wither',
	'minecraft:skeleton_horse',
	'minecraft:zombie_horse',
	'minecraft:phantom',
]

// nearest_player_name is the plugin.ServerView facing form of nearest_player.
// It resolves the runtime id back to a display name rather than leaking the
// internal runtime id concept into the plugin surface.
pub fn (mut h Hub) nearest_player_name(x f32, y f32, z f32, radius f32) ?string {
	rid, _, found := h.find_nearest_player(types.Vector3{x, y, z}, radius)
	if !found {
		return none
	}
	target := h.session_by_runtime(rid) or { return none }
	return target.name()
}

// find_nearest_player scans live sessions for the closest one to pos within
// radius, returning its runtime id, position and whether anyone was found.
// Shared by entity.Host's nearest_player (proactive mob targeting) and
// plugin.ServerView's nearest_player_name.
fn (mut h Hub) find_nearest_player(pos types.Vector3, radius f32) (u64, types.Vector3, bool) {
	mut best_rid := u64(0)
	mut best_pos := types.Vector3{}
	mut best_dist_sq := radius * radius
	mut found := false
	for mut target in h.snapshot() {
		tp := target.current_position()
		dx := tp.x - pos.x
		dy := tp.y - pos.y
		dz := tp.z - pos.z
		dist_sq := dx * dx + dy * dy + dz * dz
		if dist_sq <= best_dist_sq {
			best_rid = target.runtime_id
			best_pos = tp
			best_dist_sq = dist_sq
			found = true
		}
	}
	return best_rid, best_pos, found
}

// throw_splash_potion spawns a splash potion projectile from the player's eye
// level, offset slightly forward so it appears in front of the face rather than
// inside the head. Removes the held item unless in creative.
fn (mut s NetworkSession) throw_splash_potion(entity_type string, meta int) {
	// Vedrock stores player position at eye level (feet + 1.62).
	// Bump it up slightly so the entity clears the player head
	mut pos := s.current_position()
	pos.y += 0.1

	// Compute throw direction from pitch and yaw.
	// Apply throwableOffset: pitch correction that arcs the projectile
	// upward to compensate for hand position vs eye level.
	// Dragonfly formula: pitch -= sqrt(89.9^2 - pitch^2) * (26.5 / 89.9)
	adjusted := throwable_offset(s.pitch)
	pitch_rad := adjusted * f32(math.pi) / 180.0
	yaw_rad := s.yaw * f32(math.pi) / 180.0
	vx := -math.sinf(yaw_rad) * math.cosf(pitch_rad)
	vy := -math.sinf(pitch_rad)
	vz := math.cosf(yaw_rad) * math.cosf(pitch_rad)

	// Nudge the spawn point forward along the horizontal look direction
	// so the entity is visible in front of the player's face, not clipped
	// inside their head model. Skip when looking straight up/down.
	horiz := math.sqrtf(vx * vx + vz * vz)
	if horiz > 0.01 {
		pos.x += (vx / horiz) * 0.3
		pos.z += (vz / horiz) * 0.3
	}

	// Vanilla Bedrock potion throw speed ~ 0.5 blocks/tick.
	speed := f32(0.5)

	behaviour := &entity.SplashPotionBehaviour{
		network_id: entity_type
		meta:       meta
	}
	mut projectile := s.hub.entities.spawn(behaviour, pos)
	projectile.velocity = types.Vector3{vx * speed, vy * speed, vz * speed}
	projectile.pitch = s.pitch
	projectile.yaw = s.yaw
	// floor_y defaults to spawn y, which clamps the projectile to eye
	// level and prevents gravity from pulling it down. Set it low so
	// the potion arcs freely.
	projectile.floor_y = -64

	// Throw sound - broadcast at the player's position.
	s.hub.broadcast(&protocol.LevelSoundEventPacket{
		sound:           'random.bow'
		position:        s.current_position()
		extra_data:      -1
		entity_type:     'minecraft:player'
		actor_unique_id: i64(s.runtime_id)
	})

	// Remove the thrown item from the held slot (unless creative).
	if s.game_mode != protocol.game_type_creative
		&& s.game_mode != protocol.game_type_creative_spectator {
		s.consume_held_item()
	}
}

// throwable_offset applies a pitch correction for thrown projectiles so they
// arc upward rather than leaving straight from the crosshair. The correction is
// strongest when looking horizontally and tapers to zero when looking straight
// up or down. Dragonfly formula.
// https://github.com/df-mc/dragonfly
fn throwable_offset(pitch f32) f32 {
	p2 := pitch * pitch
	max_p2 := f32(89.9 * 89.9)
	if p2 >= max_p2 {
		return pitch
	}
	return pitch - f32(math.sqrtf(max_p2 - p2) * (26.5 / 89.9))
}
