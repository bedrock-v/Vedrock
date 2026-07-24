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

// PlayerAttackTask is handle_attack's cross session mutation on the attacker's
// owning world runtime. Attacker and victim must both be members of that world;
// otherwise the attack has no side effects.
struct PlayerAttackTask {
	attacker_runtime_id u64
	attacker_epoch      i64
	victim_runtime_id   u64
	damage              f32
	knockback_from      types.Vector3
	knockback_force     f32 = knockback_horizontal
	knockback_height    f32 = knockback_vertical
	critical            bool
}

fn (t PlayerAttackTask) run(mut tx WorldTx) {
	mut attacker := tx.player_for_epoch(t.attacker_runtime_id, t.attacker_epoch) or { return }
	victim_entry := tx.wr.players[t.victim_runtime_id] or { return }
	mut victim := victim_entry.session
	if victim.player.is_dead() || !victim.spawned
		|| victim.player.game_mode() == protocol.game_type_creative
		|| victim.player.game_mode() == protocol.game_type_spectator {
		return
	}
	mut ctx := event.new_context(event.AttackData{
		player:            attacker
		victim_runtime_id: t.victim_runtime_id
		critical:          t.critical
		damage:            t.damage
		knockback_force:   t.knockback_force
		knockback_height:  t.knockback_height
	})
	tx.wr.events.player_attack(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	tx.damage_held_item(mut attacker, 1)
	victim.apply_knockback(t.knockback_from, ctx.val.knockback_force, ctx.val.knockback_height)
	victim.apply_hurt(mut tx.wr, ctx.val.damage, attacker.player.identity.display_name)
	if t.critical {
		tx.wr.broadcast_world(&protocol.AnimatePacket{
			action:           protocol.animate_action_critical_hit
			actor_runtime_id: victim.runtime_id
		})
		tx.wr.broadcast_world(&protocol.LevelSoundEventPacket{
			sound:           sound_attack_strong
			position:        victim.current_position()
			extra_data:      -1
			entity_type:     'minecraft:player'
			actor_unique_id: i64(victim.runtime_id)
		})
	}
}

// max_attack_reach_sq caps how far an attack/entity interaction can land,
// measured from the attacker to the target.
const max_attack_reach_sq = f32(8.0 * 8.0)

fn (mut s NetworkSession) handle_attack(target_runtime_id u64) ! {
	if s.player.is_dead() || target_runtime_id == s.runtime_id {
		return
	}
	mut victim := s.hub.session_by_runtime(target_runtime_id) or { return }
	// effective_position, not player.position(): see its own comment.
	// An attack packet immediately following a movement update in the same
	// batch must be checked against where the attacker just said they are.
	own := s.effective_position()
	vp := victim.current_position()
	dx := own.x - vp.x
	dy := own.y - vp.y
	dz := own.z - vp.z
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
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	if !wr.try_submit(PlayerAttackTask{
		attacker_runtime_id: s.runtime_id
		attacker_epoch:      s.world_binding().epoch
		victim_runtime_id:   target_runtime_id
		damage:              damage
		knockback_from:      own
		critical:            critical
	}) {
		s.log.debug('Dropped attack task - actor queue full')
	}
}

// EntityInteractSnapshot is a point in time copy of the fields
// handle_entity_interact needs from a live entity.Entity, gathered on the
// owning world runtime. Session threads copy plain values and never retain the
// live entity pointer.
struct EntityInteractSnapshot {
	found      bool
	in_reach   bool
	identifier string
	pos        types.Vector3
}

// handle_entity_interact runs a UsableOnEntityItem's behaviour when a player
// uses the held item on an entity (the "interact", as opposed to "attack",
// use item onentity action) - e.g. milking a cow with an empty bucket.
fn (mut s NetworkSession) handle_entity_interact(target_runtime_id u64) {
	if s.player.is_dead() || !s.can_interact() {
		return
	}
	own := s.player.position()
	binding := s.world_binding()
	if isnil(binding.world_runtime) {
		return
	}
	mut wr := binding.world_runtime
	snap := world_call[EntityInteractSnapshot](mut wr, fn [own, target_runtime_id] (mut tx WorldTx) EntityInteractSnapshot {
		target := tx.wr.entities.by_runtime_id(target_runtime_id) or {
			return EntityInteractSnapshot{}
		}
		dx := own.x - target.pos.x
		dy := own.y - target.pos.y
		dz := own.z - target.pos.z
		return EntityInteractSnapshot{
			found:      true
			in_reach:   dx * dx + dy * dy + dz * dz <= max_attack_reach_sq
			identifier: target.identifier
			pos:        target.pos
		}
	}) or { EntityInteractSnapshot{} }
	if !snap.found || !snap.in_reach {
		return
	}
	stack, name := s.held_stack_and_name()
	result := s.hub.items.use_on_entity_result(name, snap.identifier, stack.meta) or { return }
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
			position:        snap.pos
			extra_data:      -1
			entity_type:     snap.identifier
			actor_unique_id: i64(target_runtime_id)
		})
	}
}

// replace_held_item is session local inventory work: item lookup uses shared
// readonly data and mutation goes through Player's state lock.
fn (mut s NetworkSession) replace_held_item(item_name string) {
	new_id := s.hub.data.item_id_by_name[item_name] or { return }
	new_stack := types.ItemStack{
		id:    new_id
		count: 1
	}
	net_id := s.player.track_stack(new_stack)
	held_slot := s.player.held_slot()
	s.player.set_slot(held_slot, net_id)
	wrapped := wrap_stack_id(new_stack, net_id)
	s.player.set_held(held_slot, wrapped)
	s.send_slot_update(held_slot, wrapped)
}

fn (s &NetworkSession) is_critical() bool {
	if s.player.game_mode() == protocol.game_type_creative
		|| s.player.game_mode() == protocol.game_type_spectator {
		return false
	}
	return s.player.movement().vy < -0.08
}

// apply_hurt runs only from an active world runtime. It dispatches player_hurt,
// broadcasts damage in that world and routes lethal hits through apply_death.
fn (mut s NetworkSession) apply_hurt(mut wr WorldRuntime, amount f32, attacker_name string) {
	if s.player.is_dead() || s.player.game_mode() == protocol.game_type_creative
		|| s.player.game_mode() == protocol.game_type_spectator {
		return
	}
	mut ctx := event.new_context(event.HurtData{
		player:        s
		amount:        amount
		attacker_name: attacker_name
	})
	wr.events.player_hurt(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	new_health := s.player.health() - ctx.val.amount
	s.player.set_health(if new_health < 0 { f32(0) } else { new_health })
	s.deliver(s.health_update())
	wr.broadcast_world(&protocol.ActorEventPacket{
		actor_runtime_id: s.runtime_id
		event_id:         protocol.actor_event_hurt
		event_data:       0
	})
	if s.player.health() <= 0 {
		s.apply_death(mut wr, '%death.attack.player',
			[s.player.identity.display_name, attacker_name])
	}
}

// apply_death is the single death path for combat, /kill and fatal effect
// damage.
fn (mut s NetworkSession) apply_death(mut wr WorldRuntime, message_key string, parameters []string) {
	mut ctx := event.new_context(event.DeathData{
		player:      s
		message_key: message_key
		params:      parameters
	})
	wr.events.player_death(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	s.player.set_dead(true)
	wr.broadcast_world_except(s.runtime_id, &protocol.ActorEventPacket{
		actor_runtime_id: s.runtime_id
		event_id:         protocol.actor_event_death
		event_data:       0
	})
	s.player.set_last_death(s.current_position())
	wr.broadcast_world(&protocol.TextPacket{
		@type:             int(enums.TextType.translation)
		needs_translation: true
		message:           ctx.val.message_key
		parameters:        parameters
	})
}

// PlayerRespawnTask respawns a player on the owning world runtime. Respawn
// does not transfer dimensions; the destination is the player's current world
// and generator.
struct PlayerRespawnTask {
	runtime_id u64
	epoch      i64
}

fn (t PlayerRespawnTask) run(mut tx WorldTx) {
	mut target := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	target.apply_respawn(mut tx.wr)
}

fn (mut s NetworkSession) handle_respawn(p protocol.RespawnPacket) ! {
	if p.respawn_state == protocol.respawn_state_client_ready {
		s.request_respawn()
	}
}

// request_respawn is the single entry point for respawning a player.
fn (mut s NetworkSession) request_respawn() {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	if !wr.try_submit(PlayerRespawnTask{
		runtime_id: s.runtime_id
		epoch:      s.world_binding().epoch
	}) {
		s.log.debug('Dropped respawn task - actor queue full')
	}
}

fn (mut s NetworkSession) apply_respawn(mut wr WorldRuntime) {
	if !s.player.is_dead() {
		return
	}
	s.player.set_dead(false)
	s.player.set_health(20.0)
	spawn_y := s.generator.spawn_y()
	mut ctx := event.new_context(event.RespawnData{
		player: s
		x:      0.0
		y:      f32(spawn_y) + player_eye_height
		z:      0.0
	})
	wr.events.player_respawn(mut ctx)
	s.player.reset_position(types.Vector3{ctx.val.x, ctx.val.y, ctx.val.z})
	current := s.player.movement()
	s.deliver(s.health_update())
	s.deliver(&protocol.RespawnPacket{
		position:         current.position
		respawn_state:    protocol.respawn_state_ready_to_spawn
		actor_runtime_id: s.runtime_id
	})
	s.deliver(&protocol.MovePlayerPacket{
		actor_runtime_id: s.runtime_id
		position:         current.position
		pitch:            current.pitch
		yaw:              current.yaw
		head_yaw:         current.head_yaw
		mode:             1
		on_ground:        false
	})
	// Remote clients played the death animation; respawn the actor for them.
	wr.broadcast_world_except(s.runtime_id, s.remove_actor_packet())
	wr.broadcast_world_except(s.runtime_id, s.add_player_packet())
}

// current_position is a thin forwarding accessor kept for call site
// continuity, the actual lock lives on Player (see player.Player's
// movement()/position() comment).
fn (mut s NetworkSession) current_position() types.Vector3 {
	return s.player.position()
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
	s.deliver(&protocol.SetActorMotionPacket{
		actor_runtime_id: s.runtime_id
		motion:           motion
		tick:             0
	})
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
