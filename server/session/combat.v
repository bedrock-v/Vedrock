module session

import math
import protocol
import protocol.types
import protocol.enums
import server.item

const knockback_horizontal = f32(0.4)
const knockback_vertical = f32(0.4)
const critical_multiplier = f32(1.5)
const sound_attack_strong = 'game.player.attack.strong'

fn (mut s NetworkSession) handle_attack(target_runtime_id u64, held types.ItemStackWrapper) ! {
	if s.dead {
		return
	}
	mut victim := s.hub.session_by_runtime(target_runtime_id) or { return }
	if victim.runtime_id == s.runtime_id || victim.dead || !victim.spawned {
		return
	}
	if victim.game_mode == protocol.game_type_creative
		|| victim.game_mode == protocol.game_type_spectator {
		return
	}
	mut damage := s.weapon_damage(s.hub.data.item_name(held.item_stack.id))
	critical := s.is_critical()
	if critical {
		damage *= critical_multiplier
	}
	victim.apply_knockback(s.position)
	victim.take_damage(damage, s.identity.display_name)
	if critical {
		s.broadcast_critical(victim.runtime_id, victim.position)
	}
}

fn (mut s NetworkSession) broadcast_critical(target_runtime_id u64, position types.Vector3) {
	s.hub.broadcast(&protocol.AnimatePacket{
		action:           protocol.animate_action_critical_hit
		actor_runtime_id: target_runtime_id
	})
	s.hub.broadcast(&protocol.LevelSoundEventPacket{
		sound:           sound_attack_strong
		position:        position
		extra_data:      -1
		entity_type:     'minecraft:player'
		actor_unique_id: i64(target_runtime_id)
	})
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
	s.health -= amount
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
		s.die(attacker_name)
	}
}

fn (mut s NetworkSession) die(attacker_name string) {
	s.dead = true
	s.hub.broadcast_except(s.runtime_id, &protocol.ActorEventPacket{
		actor_runtime_id: s.runtime_id
		event_id:         protocol.actor_event_death
		event_data:       0
	})
	s.hub.broadcast(&protocol.TextPacket{
		@type:             int(enums.TextType.translation)
		needs_translation: true
		message:           '%death.attack.player'
		parameters:        [s.identity.display_name, attacker_name]
	})
}

fn (mut s NetworkSession) handle_respawn(p protocol.RespawnPacket) ! {
	if p.respawn_state == protocol.respawn_state_client_ready {
		s.respawn()
	}
}

fn (mut s NetworkSession) respawn() {
	if !s.dead {
		return
	}
	s.dead = false
	s.health = 20.0
	spawn_y := s.generator.spawn_y()
	s.position = types.Vector3{0.0, f32(spawn_y) + player_eye_height, 0.0}
	s.prev_y = s.position.y
	s.vy = 0.0
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

fn (mut s NetworkSession) apply_knockback(from types.Vector3) {
	mut dx := s.position.x - from.x
	mut dz := s.position.z - from.z
	mut dist := math.sqrtf(dx * dx + dz * dz)
	if dist < 0.0001 {
		dx = 0.0
		dz = 0.0
		dist = 1.0
	}
	motion := types.Vector3{
		x: dx / dist * knockback_horizontal
		y: knockback_vertical
		z: dz / dist * knockback_horizontal
	}
	s.transport.send(&protocol.SetActorMotionPacket{
		actor_runtime_id: s.runtime_id
		motion:           motion
		tick:             0
	}) or {}
}

// weapon_damage prefers the damage from a registered SwordItem class and falls
// back to the material-tier heuristic for items without a modelled class.
fn (s &NetworkSession) weapon_damage(name string) f32 {
	if it := s.hub.items.get(name) {
		if it is item.SwordItem {
			return f32(it.damage())
		}
	}
	return weapon_damage_heuristic(name)
}

fn weapon_damage_heuristic(name string) f32 {
	tier := material_tier(name)
	if name.contains('_sword') {
		return [f32(4.0), 5.0, 6.0, 7.0, 8.0][tier]
	}
	if name.contains('_axe') {
		return [f32(7.0), 9.0, 9.0, 9.0, 10.0][tier]
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
