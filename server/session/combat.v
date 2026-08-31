module session

import math
import bedrock_v.protocol.types
import server.effect
import server.event
import server.item
import bedrock_v.protocol.current as proto

const knockback_horizontal = f32(0.4)
const knockback_vertical = f32(0.4)
const critical_multiplier = f32(1.5)
const sound_attack_strong = 'game.player.attack.strong'

// PlayerAttackTask is handle_attack's cross session mutation on the attacker's
// owning world runtime. Attacker and victim must both be members of that world;
// otherwise the attack has no side effects. The victim may be a player or a
// registered mob. Resolved through the unified actor lookup since a player's
// melee attack has no reason to be restricted to player-vs-player.
struct PlayerAttackTask {
	attacker_runtime_id u64
	attacker_epoch      i64
	victim_runtime_id   u64
	damage              f32
	knockback_force     f32 = knockback_horizontal
	knockback_height    f32 = knockback_vertical
	critical            bool
}

fn (t PlayerAttackTask) name() string {
	return 'PlayerAttackTask'
}

fn (t PlayerAttackTask) run(mut tx WorldTx) {
	mut attacker := tx.player_for_epoch(t.attacker_runtime_id, t.attacker_epoch) or { return }
	mut victim_actor := tx.wr.entities.actor_by_runtime_id(t.victim_runtime_id) or { return }
	if victim_actor.is_dead() {
		return
	}
	// The reach check runs here, not before submission.
	own := attacker.effective_position()
	vp := victim_actor.current_position()
	dx := own.x - vp.x
	dy := own.y - vp.y
	dz := own.z - vp.z
	if dx * dx + dy * dy + dz * dz > max_attack_reach_sq {
		return
	}
	if mut victim_actor is NetworkSession {
		if !victim_actor.spawned || !victim_actor.player.game_mode().allows_taking_damage() {
			return
		}
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
	damage_actor(mut tx.wr, t.victim_runtime_id, ctx.val.damage, AttackDamageSource{
		attacker_name: attacker.player.identity.display_name
	}, t.attacker_runtime_id, own, ctx.val.knockback_force, ctx.val.knockback_height)
	if t.critical {
		tx.wr.broadcast_world(&proto.AnimatePacket{
			action:            proto.AnimatePacketAction.critical_hit
			target_runtime_id: proto.actor_runtime_id(victim_actor.runtime_id())
		})
		tx.wr.broadcast_world(proto.level_sound_event(sound_attack_strong,
			victim_actor.current_position(), -1, 'minecraft:player', victim_actor.runtime_id()))
	}
}

// max_attack_reach_sq caps how far an attack/entity interaction can land,
// measured from the attacker to the target.
const max_attack_reach_sq = f32(8.0 * 8.0)

fn (mut s NetworkSession) handle_attack(target_runtime_id u64) ! {
	if s.player.is_dead() || target_runtime_id == s.runtime_id {
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
	// A hit must not be silently dropped under queue pressure.
	wr.submit(PlayerAttackTask{
		attacker_runtime_id: s.runtime_id
		attacker_epoch:      s.world_binding().epoch
		victim_runtime_id:   target_runtime_id
		damage:              damage
		critical:            critical
	})
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
	result := item.use_on_entity_result(name, snap.identifier, stack.meta) or { return }
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
		s.hub.broadcast(proto.level_sound_event(result.sound, snap.pos, -1, snap.identifier,
			target_runtime_id))
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
	if !s.player.game_mode().allows_taking_damage() {
		return false
	}
	return s.player.movement().vy < -0.08
}

// apply_hurt runs only from an active world runtime. It dispatches player_hurt,
// broadcasts damage in that world and routes lethal hits through apply_death.
//
// source decides fire resistance immunity and resistance effect reduction
// (see DamageSource, damage_source.v) and supplies the
// death message. Effect damage doesn't go through here.
fn (mut s NetworkSession) apply_hurt(mut wr WorldRuntime, amount f32, source DamageSource) {
	if s.player.is_dead() || !s.player.game_mode().allows_taking_damage() {
		return
	}
	if source.ignored_by_fire_resistance() {
		if _ := s.player.effect(effect.fire_resistance) {
			return
		}
	}
	mut reduced_amount := amount
	if source.reduced_by_resistance() {
		if res := s.player.effect(effect.resistance) {
			reduced_amount *= resistance_multiplier(res.level())
		}
	}
	if reduced_amount <= 0 {
		return
	}
	mut ctx := event.new_context(event.HurtData{
		player:        s
		amount:        reduced_amount
		attacker_name: source.attacker_label()
	})
	wr.events.player_hurt(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	new_health := s.player.health() - ctx.val.amount
	s.player.set_health(if new_health < 0 { f32(0) } else { new_health })
	s.deliver(s.health_update())
	wr.broadcast_world(&proto.ActorEventPacket{
		target_runtime_id: proto.actor_runtime_id(s.runtime_id)
		event_id:          proto.ActorEvent.hurt
		data:              0
	})
	if s.player.health() <= 0 {
		key, params := source.death_message_key(s.player.identity.display_name)
		s.apply_death(mut wr, key, params)
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
	wr.broadcast_world_except(s.runtime_id, &proto.ActorEventPacket{
		target_runtime_id: proto.actor_runtime_id(s.runtime_id)
		event_id:          proto.ActorEvent.death
		data:              0
	})
	s.player.set_last_death(s.current_position())
	wr.broadcast_world(&proto.TextPacket{
		localize:     true
		message_type: proto.TextTranslate{
			message:        ctx.val.message_key
			parameter_list: parameters
		}
	})
}

// PlayerRespawnTask respawns a player on the owning world runtime. Respawn
// does not transfer dimensions; the destination is the player's current world
// and generator.
struct PlayerRespawnTask {
	runtime_id u64
	epoch      i64
}

fn (t PlayerRespawnTask) name() string {
	return 'PlayerRespawnTask'
}

fn (t PlayerRespawnTask) run(mut tx WorldTx) {
	mut target := tx.player_for_epoch(t.runtime_id, t.epoch) or { return }
	target.apply_respawn(mut tx.wr)
}

fn (mut s NetworkSession) handle_respawn(p proto.RespawnPacket) ! {
	if p.state == proto.PlayerRespawnState.client_ready_to_spawn {
		s.request_respawn()
	}
}

// request_respawn is the single entry point for respawning a player.
fn (mut s NetworkSession) request_respawn() {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	// A dropped respawn has no natural retry. The client only sends
	// client_ready_to_spawn once, so losing it under queue pressure could
	// leave the player stuck on the death screen.
	wr.submit(PlayerRespawnTask{
		runtime_id: s.runtime_id
		epoch:      s.world_binding().epoch
	})
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
	mut respawn_packet := &proto.RespawnPacket{
		state:             proto.PlayerRespawnState.ready_to_spawn
		player_runtime_id: proto.actor_runtime_id(s.runtime_id)
	}
	respawn_packet.position[0] = current.position.x
	respawn_packet.position[1] = current.position.y
	respawn_packet.position[2] = current.position.z
	s.deliver(respawn_packet)
	mut move_packet := &proto.MovePlayerPacket{
		player_runtime_id: proto.actor_runtime_id(s.runtime_id)
		y_head_rotation:   current.head_yaw
		position_mode:     proto.PlayerPositionMode.respawn
		on_ground:         false
	}
	move_packet.position[0] = current.position.x
	move_packet.position[1] = current.position.y
	move_packet.position[2] = current.position.z
	move_packet.rotation[0] = current.pitch
	move_packet.rotation[1] = current.yaw
	s.deliver(move_packet)
	s.expect_teleport_ack(current.position)
	// Remote clients played the death animation; respawn the actor for them.
	wr.broadcast_world_except(s.runtime_id, s.remove_actor_packet())
	wr.broadcast_world_except(s.runtime_id, s.add_player_packet())
}

// current_position is a thin forwarding accessor kept for call site
// continuity, the actual lock lives on Player (see player.Player's
// movement()/position() comment).
fn (s &NetworkSession) current_position() types.Vector3 {
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
	mut motion_packet := &proto.SetActorMotionPacket{
		target_runtime_id: proto.actor_runtime_id(s.runtime_id)
		server_tick:       0
	}
	motion_packet.motion[0] = motion.x
	motion_packet.motion[1] = motion.y
	motion_packet.motion[2] = motion.z
	s.deliver(motion_packet)
}

// weapon_damage prefers the damage from a registered weapon class and falls
// back to the material-tier heuristic for items without a modelled class.
fn (s &NetworkSession) weapon_damage(name string) f32 {
	if it := item.get(name) {
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
