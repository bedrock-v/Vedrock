module session

import math
import server.effect
import server.event
import bedrock_v.protocol.current as proto
import server.player
import server.worldrt

const mob_effect_add = proto.MobEffectEvent.add
const mob_effect_remove = proto.MobEffectEvent.remove

// PlayerAddEffectTask/PlayerRemoveEffectTask are add_effect()/remove_effect()
// run through the owning world's actor. epoch is checked via
// player_for_epoch so a stale request (submitted before a world switch)
// produces zero side effects, same as the block-write tasks.
struct PlayerAddEffectTask {
	runtime_id u64
	epoch      i64
	effect     effect.Effect
}

fn (t PlayerAddEffectTask) name() string {
	return 'PlayerAddEffectTask'
}

fn (t PlayerAddEffectTask) run(mut tx worldrt.WorldTx) {
	mut s := player_for_epoch(mut tx, t.runtime_id, t.epoch) or { return }
	s.apply_add_effect(mut tx.wr, t.effect)
}

struct PlayerRemoveEffectTask {
	runtime_id u64
	epoch      i64
	typ        effect.Type
}

fn (t PlayerRemoveEffectTask) name() string {
	return 'PlayerRemoveEffectTask'
}

fn (t PlayerRemoveEffectTask) run(mut tx worldrt.WorldTx) {
	mut s := player_for_epoch(mut tx, t.runtime_id, t.epoch) or { return }
	s.apply_remove_effect(mut tx.wr, t.typ)
}

fn (mut s NetworkSession) add_effect(e effect.Effect) {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	wr.submit(PlayerAddEffectTask{
		runtime_id: s.runtime_id
		epoch:      s.world_binding().epoch
		effect:     e
	})
}

fn (mut s NetworkSession) remove_effect(typ effect.Type) {
	mut wr := s.current_world_runtime()
	if isnil(wr) {
		return
	}
	wr.submit(PlayerRemoveEffectTask{
		runtime_id: s.runtime_id
		epoch:      s.world_binding().epoch
		typ:        typ
	})
}

// Effect mutation receives the owning runtime explicitly because event
// dispatch, effect packets and effect damage are world scoped.
fn (mut s NetworkSession) apply_add_effect(mut wr worldrt.WorldRuntime, e effect.Effect) {
	mut ctx := event.new_context(player.EffectAddData{
		effect_name:    e.effect_type().name
		level:          e.level()
		duration_ticks: e.duration_ticks()
		player:         s.player
	})
	s.player.handler.on_effect_add(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	result := s.player.add_effect_result(e)
	if result.accepted {
		if result.replaced {
			s.apply_effect_end(result.previous)
		}
		s.apply_effect_start(result.effect)
		if !result.stored {
			s.apply_effect_tick(mut wr, result.effect)
		}
	}
	s.send_effect(mut wr, result.effect)
}

fn (mut s NetworkSession) apply_remove_effect(mut wr worldrt.WorldRuntime, typ effect.Type) {
	mut ctx := event.new_context(player.EffectRemoveData{
		effect_name: typ.name
		player:      s.player
	})
	s.player.handler.on_effect_remove(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	removed := s.player.remove_effect(typ) or { return }
	s.apply_effect_end(removed)
	s.send_effect_removal(mut wr, typ)
}

// tick_effects advances one player's active effects during the owning world's
// simulation step. Environmental damage and death stay on that world's
// runtime.
fn (mut s NetworkSession) tick_effects(mut wr worldrt.WorldRuntime) {
	result := s.player.tick_effects()
	for e in result.active {
		s.apply_effect_tick(mut wr, e)
	}
	for e in result.expired {
		s.apply_effect_end(e)
		s.send_effect_removal(mut wr, e.effect_type())
	}
}

fn (mut s NetworkSession) send_active_effects(mut wr worldrt.WorldRuntime) {
	for e in s.player.active_effects() {
		s.send_effect(mut wr, e)
	}
}

fn (mut s NetworkSession) send_effect(mut wr worldrt.WorldRuntime, e effect.Effect) {
	s.send_effect_removal(mut wr, e.effect_type())
	s.send_mob_effect(mut wr, e, mob_effect_add)
}

// Effect packets are visible only to players in the same world.
fn (mut s NetworkSession) send_effect_removal(mut wr worldrt.WorldRuntime, typ effect.Type) {
	if !s.spawned {
		return
	}
	wr.broadcast_world(&proto.MobEffectPacket{
		target_runtime_id: proto.actor_runtime_id(s.runtime_id)
		event_id:          mob_effect_remove
		effect_id:         typ.id
	})
}

fn (mut s NetworkSession) send_mob_effect(mut wr worldrt.WorldRuntime, e effect.Effect, event_id proto.MobEffectEvent) {
	if !s.spawned {
		return
	}
	wr.broadcast_world(s.mob_effect_packet(e, event_id))
}

fn (s &NetworkSession) mob_effect_packet(e effect.Effect, event_id proto.MobEffectEvent) &proto.MobEffectPacket {
	return &proto.MobEffectPacket{
		target_runtime_id:     proto.actor_runtime_id(s.runtime_id)
		event_id:              event_id
		effect_id:             e.effect_type().id
		effect_amplifier:      e.level() - 1
		show_particles:        !e.particles_hidden()
		effect_duration_ticks: e.duration_ticks()
		tick:                  u64(e.tick())
		ambient:               e.ambient()
	}
}

fn (mut s NetworkSession) apply_effect_start(e effect.Effect) {
	match e.effect_type().id {
		effect.absorption.id {
			s.send_health()
		}
		else {}
	}
}

fn (mut s NetworkSession) apply_effect_end(e effect.Effect) {
	match e.effect_type().id {
		effect.absorption.id {
			s.send_health()
		}
		else {}
	}
}

fn (mut s NetworkSession) apply_effect_tick(mut wr worldrt.WorldRuntime, e effect.Effect) {
	match e.effect_type().id {
		effect.instant_health.id {
			amount := f32((2 << e.level())) * f32(e.potency())
			s.heal(amount)
		}
		effect.instant_damage.id {
			amount := f32((3 << e.level())) * f32(e.potency())
			s.apply_damage_from_effect(mut wr, amount, true)
		}
		effect.regeneration.id {
			interval := math.max(50 >> (e.level() - 1), 1)
			if e.tick() % interval == 0 {
				s.heal(1)
			}
		}
		effect.poison.id {
			interval := math.max(50 >> (e.level() - 1), 1)
			if e.tick() % interval == 0 && s.player.health() > 1 {
				s.apply_damage_from_effect(mut wr, 1, false)
			}
		}
		effect.wither.id, effect.fatal_poison.id {
			interval := math.max(80 >> e.level(), 1)
			if e.tick() % interval == 0 {
				s.apply_damage_from_effect(mut wr, 1, true)
			}
		}
		else {}
	}
}

fn (mut s NetworkSession) heal(amount f32) {
	if s.player.is_dead() || amount <= 0 {
		return
	}
	old := s.player.health()
	mut new_health := old + amount
	if new_health > 20 {
		new_health = 20
	}
	s.player.set_health(new_health)
	if new_health != old {
		s.send_health()
	}
}

// apply_damage_from_effect handles damage caused by effects. Poison style
// non-fatal damage floors at one health; fatal effects may kill and use
// Player.die so all deaths share one path. Effect damage has no attacker, so
// it does not dispatch player_hurt.
fn (mut s NetworkSession) apply_damage_from_effect(mut wr worldrt.WorldRuntime, amount f32, fatal bool) {
	if s.player.is_dead() || amount <= 0 || !s.player.game_mode().allows_taking_damage() {
		return
	}
	if !fatal && s.player.health() - amount < 1 {
		s.player.set_health(1)
	} else {
		s.player.set_health(s.player.health() - amount)
	}
	if s.player.health() < 0 {
		s.player.set_health(0)
	}
	s.send_health()
	if s.spawned {
		wr.broadcast_world(&proto.ActorEventPacket{
			target_runtime_id: proto.actor_runtime_id(s.runtime_id)
			event_id:          proto.ActorEvent.hurt
			data:              0
		})
	}
	if s.player.health() <= 0 {
		key, params := MagicDamageSource{}.death_message_key(s.player.identity.display_name)
		s.player.die(mut wr, key, params)
	}
}

fn (mut s NetworkSession) send_health() {
	if !s.spawned {
		return
	}
	s.deliver(s.health_update())
}
