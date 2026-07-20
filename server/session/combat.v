module session

import math
import protocol
import protocol.types
import protocol.enums
import server.event

const knockback_horizontal = f32(0.4)
const knockback_vertical = f32(0.4)
const critical_multiplier = f32(1.5)
const sound_attack_strong = 'game.player.attack.strong'

// DamageJob is combat's cross-session mutation as a WorldJob.
struct DamageJob {
	victim_runtime_id u64
	amount            f32
	attacker_name     string
	knockback_from    types.Vector3
	knockback_force   f32 = knockback_horizontal
	knockback_height  f32 = knockback_vertical
	critical          bool
}

fn (j DamageJob) run(mut h Hub) {
	mut victim := h.session_by_runtime(j.victim_runtime_id) or { return }
	if victim.dead || !victim.spawned || victim.game_mode == protocol.game_type_creative
		|| victim.game_mode == protocol.game_type_spectator {
		return
	}
	victim.apply_knockback(j.knockback_from, j.knockback_force, j.knockback_height)
	victim.take_damage(j.amount, j.attacker_name)
	if j.critical {
		h.broadcast(&protocol.AnimatePacket{
			action:           protocol.animate_action_critical_hit
			actor_runtime_id: victim.runtime_id
		})
		h.broadcast(&protocol.LevelSoundEventPacket{
			sound:           sound_attack_strong
			position:        victim.current_position()
			extra_data:      -1
			entity_type:     'minecraft:player'
			actor_unique_id: i64(victim.runtime_id)
		})
	}
}

// max_attack_reach_sq caps how far an attack can land, measured from the
// attacker to the victim. Bedrock melee reach is ~3 blocks; the extra padding
// absorbs latency while still rejecting kill-aura hits from across the map.
const max_attack_reach_sq = f32(6.0 * 6.0)

fn (mut s NetworkSession) handle_attack(target_runtime_id u64) ! {
	if s.dead || target_runtime_id == s.runtime_id {
		return
	}
	mut victim := s.hub.session_by_runtime(target_runtime_id) or { return }
	vp := victim.current_position()
	dx := s.position.x - vp.x
	dy := s.position.y - vp.y
	dz := s.position.z - vp.z
	if dx * dx + dy * dy + dz * dz > max_attack_reach_sq {
		return
	}
	// Damage comes from the server-side inventory at the held slot, never the
	// client-supplied held item - otherwise a client could claim a weapon it
	// does not own to inflate damage.
	_, weapon_name := s.held_stack_and_name()
	mut damage := s.weapon_damage(weapon_name)
	critical := s.is_critical()
	if critical {
		damage *= critical_multiplier
	}
	mut ctx := event.new_context(event.AttackData{
		player:            s
		victim_runtime_id: target_runtime_id
		critical:          critical
		damage:            damage
		knockback_force:   knockback_horizontal
		knockback_height:  knockback_vertical
	})
	s.hub.events.player_attack(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	s.damage_held_item(1)
	if !s.hub.try_submit(DamageJob{
		victim_runtime_id: target_runtime_id
		amount:            ctx.val.damage
		attacker_name:     s.identity.display_name
		knockback_from:    s.position
		knockback_force:   ctx.val.knockback_force
		knockback_height:  ctx.val.knockback_height
		critical:          critical
	}) {
		s.log.debug('Dropped attack job - actor queue full')
	}
}

// handle_entity_interact runs a UsableOnEntityItem's behaviour when a player
// uses the held item on an entity (the "interact", as opposed to "attack",
// use item onentity action) - e.g. milking a cow with an empty bucket.
fn (mut s NetworkSession) handle_entity_interact(target_runtime_id u64) {
	if s.dead || !s.can_interact() {
		return
	}
	target := s.hub.entities.by_runtime_id(target_runtime_id) or { return }
	dx := s.position.x - target.pos.x
	dy := s.position.y - target.pos.y
	dz := s.position.z - target.pos.z
	if dx * dx + dy * dy + dz * dz > max_attack_reach_sq {
		return
	}
	stack, name := s.held_stack_and_name()
	result := s.hub.items.use_on_entity_result(name, target.identifier, stack.meta) or { return }
	mut ctx := event.new_context(event.ItemUseData{
		player:    s
		item_name: name
		meta:      stack.meta
	})
	s.hub.events.item_use(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	if result.replaces_with != '' {
		s.replace_held_item(result.replaces_with)
	}
	if result.sound != '' {
		s.hub.broadcast(&protocol.LevelSoundEventPacket{
			sound:           result.sound
			position:        target.pos
			extra_data:      -1
			entity_type:     target.identifier
			actor_unique_id: i64(target.runtime_id)
		})
	}
}

// replace_held_item swaps the held stack for a single new item id, reusing
// the same slot-bookkeeping primitives consume_held_item uses to decrement.
fn (mut s NetworkSession) replace_held_item(item_name string) {
	new_id := s.hub.data.item_id_by_name[item_name] or { return }
	new_stack := types.ItemStack{
		id:    new_id
		count: 1
	}
	net_id := s.track_stack(new_stack)
	s.inv_slots[s.held_slot] = net_id
	wrapped := wrap_stack_id(new_stack, net_id)
	s.held_item = wrapped
	s.send_slot_update(s.held_slot, wrapped)
}

fn (s &NetworkSession) is_critical() bool {
	if s.game_mode == protocol.game_type_creative || s.game_mode == protocol.game_type_spectator {
		return false
	}
	return s.vy < -0.08
}

fn (mut s NetworkSession) take_damage(amount f32, attacker_name string) {
	if s.dead || s.game_mode == protocol.game_type_creative
		|| s.game_mode == protocol.game_type_spectator {
		return
	}
	mut ctx := event.new_context(event.HurtData{
		player:        s
		amount:        amount
		attacker_name: attacker_name
	})
	s.hub.events.player_hurt(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	s.health -= ctx.val.amount
	if s.health < 0 {
		s.health = 0
	}
	s.transport.send(s.health_update()) or {}
	s.hub.broadcast(&protocol.ActorEventPacket{
		actor_runtime_id: s.runtime_id
		event_id:         protocol.actor_event_hurt
		event_data:       0
	})
	if s.health <= 0 {
		s.die('%death.attack.player', [s.identity.display_name, attacker_name])
	}
}

fn (mut s NetworkSession) die(message_key string, parameters []string) {
	mut ctx := event.new_context(event.DeathData{
		player:      s
		message_key: message_key
		params:      parameters
	})
	s.hub.events.player_death(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	s.dead = true
	s.hub.broadcast_except(s.runtime_id, &protocol.ActorEventPacket{
		actor_runtime_id: s.runtime_id
		event_id:         protocol.actor_event_death
		event_data:       0
	})
	s.has_last_death = true
	s.last_death_pos = s.current_position()
	s.hub.broadcast(&protocol.TextPacket{
		@type:             int(enums.TextType.translation)
		needs_translation: true
		message:           ctx.val.message_key
		parameters:        parameters
	})
}

// RespawnJob is respawn() run through the actor. respawn() writes
// dead/health/position, the same fields DamageJob writes, so it must run
// exclusively on run_jobs()'s thread. Same as combat.
struct RespawnJob {
	runtime_id u64
}

fn (j RespawnJob) run(mut h Hub) {
	mut target := h.session_by_runtime(j.runtime_id) or { return }
	target.respawn()
}

fn (mut s NetworkSession) handle_respawn(p protocol.RespawnPacket) ! {
	if p.respawn_state == protocol.respawn_state_client_ready {
		if !s.hub.try_submit(RespawnJob{
			runtime_id: s.runtime_id
		}) {
			s.log.debug('Dropped respawn job - actor queue full')
		}
	}
}

fn (mut s NetworkSession) respawn() {
	if !s.dead {
		return
	}
	s.dead = false
	s.health = 20.0
	spawn_y := s.generator.spawn_y()
	mut ctx := event.new_context(event.RespawnData{
		player: s
		x:      0.0
		y:      f32(spawn_y) + player_eye_height
		z:      0.0
	})
	s.hub.events.player_respawn(mut ctx)
	s.pos_mutex.lock()
	s.position = types.Vector3{ctx.val.x, ctx.val.y, ctx.val.z}
	s.prev_y = s.position.y
	s.vy = 0.0
	s.pos_mutex.unlock()
	s.transport.send(s.health_update()) or {}
	s.transport.send(&protocol.RespawnPacket{
		position:         s.position
		respawn_state:    protocol.respawn_state_ready_to_spawn
		actor_runtime_id: s.runtime_id
	}) or {}
	s.transport.send(&protocol.MovePlayerPacket{
		actor_runtime_id: s.runtime_id
		position:         s.position
		pitch:            s.pitch
		yaw:              s.yaw
		head_yaw:         s.head_yaw
		mode:             1
		on_ground:        false
	}) or {}
	// Remote clients played the death animation; respawn the actor for them.
	s.hub.broadcast_except(s.runtime_id, s.remove_actor_packet())
	s.hub.broadcast_except(s.runtime_id, s.add_player_packet())
}

// current_position is the only safe way to read position from run_jobs():
// update_movement writes position on the session's own connection thread
// under the same pos_mutex. See the pos_mutex field comment in session.v.
fn (mut s NetworkSession) current_position() types.Vector3 {
	s.pos_mutex.lock()
	defer { s.pos_mutex.unlock() }
	return s.position
}

fn (mut s NetworkSession) apply_knockback(from types.Vector3, force f32, height f32) {
	pos := s.current_position()
	mut dx := pos.x - from.x
	mut dz := pos.z - from.z
	mut dist := math.sqrtf(dx * dx + dz * dz)
	if dist < 0.0001 {
		dx = 0.0
		dz = 0.0
		dist = 1.0
	}
	motion := types.Vector3{
		x: dx / dist * force
		y: height
		z: dz / dist * force
	}
	s.transport.send(&protocol.SetActorMotionPacket{
		actor_runtime_id: s.runtime_id
		motion:           motion
		tick:             0
	}) or {}
}

// weapon_damage prefers the damage from a registered weapon class and falls
// back to the material-tier heuristic for items without a modelled class.
fn (s &NetworkSession) weapon_damage(name string) f32 {
	if it := s.hub.items.get(name) {
		if it.attack_damage() > 0 {
			return it.attack_damage()
		}
	}
	return weapon_damage_heuristic(name)
}

fn weapon_damage_heuristic(name string) f32 {
	tier := material_tier(name)
	if name.contains('_sword') {
		return [f32(5.0), 6.0, 7.0, 8.0, 9.0][tier]
	}
	if name.contains('_axe') {
		return [f32(4.0), 5.0, 6.0, 7.0, 8.0][tier]
	}
	return 1.0
}

fn material_tier(name string) int {
	return match true {
		name.contains('stone_') { 1 }
		name.contains('iron_') { 2 }
		name.contains('diamond_') { 3 }
		name.contains('netherite_') { 4 }
		else { 0 }
	}
}
