module session

import math
import protocol
import server.effect
import server.event

const mob_effect_add = 1
const mob_effect_remove = 3

struct AddEffectJob {
	runtime_id u64
	effect     effect.Effect
}

fn (j AddEffectJob) run(mut h Hub) {
	mut target := h.session_by_runtime(j.runtime_id) or { return }
	target.apply_add_effect(j.effect)
}

struct RemoveEffectJob {
	runtime_id u64
	typ        effect.Type
}

fn (j RemoveEffectJob) run(mut h Hub) {
	mut target := h.session_by_runtime(j.runtime_id) or { return }
	target.apply_remove_effect(j.typ)
}

pub fn (mut s NetworkSession) add_effect(e effect.Effect) {
	s.hub.submit(AddEffectJob{
		runtime_id: s.runtime_id
		effect:     e
	})
}

pub fn (mut s NetworkSession) remove_effect(typ effect.Type) {
	s.hub.submit(RemoveEffectJob{
		runtime_id: s.runtime_id
		typ:        typ
	})
}

fn (mut s NetworkSession) apply_add_effect(e effect.Effect) {
	mut ctx := event.new_context(event.EffectAddData{
		effect_name:    e.effect_type().name
		level:          e.level()
		duration_ticks: e.duration_ticks()
		player:         s
	})
	s.hub.events.effect_add(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	result := s.effects.add_result(e)
	if result.accepted {
		if result.replaced {
			s.apply_effect_end(result.previous)
		}
		s.apply_effect_start(result.effect)
		if !result.stored {
			s.apply_effect_tick(result.effect)
		}
	}
	s.send_effect(result.effect)
}

fn (mut s NetworkSession) apply_remove_effect(typ effect.Type) {
	mut ctx := event.new_context(event.EffectRemoveData{
		effect_name: typ.name
		player:      s
	})
	s.hub.events.effect_remove(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	removed := s.effects.remove(typ) or { return }
	s.apply_effect_end(removed)
	s.send_effect_removal(typ)
}

fn (mut h Hub) tick_effects() {
	for mut target in h.snapshot() {
		target.tick_effects()
	}
}

fn (mut s NetworkSession) tick_effects() {
	result := s.effects.tick()
	for e in result.active {
		s.apply_effect_tick(e)
	}
	for e in result.expired {
		s.apply_effect_end(e)
		s.send_effect_removal(e.effect_type())
	}
}

fn (mut s NetworkSession) send_active_effects() {
	for e in s.effects.effects() {
		s.send_effect(e)
	}
}

fn (mut s NetworkSession) send_effect(e effect.Effect) {
	s.send_effect_removal(e.effect_type())
	s.send_mob_effect(e, mob_effect_add)
}

fn (mut s NetworkSession) send_effect_removal(typ effect.Type) {
	if !s.spawned {
		return
	}
	s.hub.broadcast(&protocol.MobEffectPacket{
		actor_runtime_id: s.runtime_id
		event_id:         mob_effect_remove
		effect_id:        typ.id
	})
}

fn (mut s NetworkSession) send_mob_effect(e effect.Effect, event_id int) {
	if !s.spawned {
		return
	}
	s.hub.broadcast(s.mob_effect_packet(e, event_id))
}

fn (s &NetworkSession) mob_effect_packet(e effect.Effect, event_id int) &protocol.MobEffectPacket {
	return &protocol.MobEffectPacket{
		actor_runtime_id: s.runtime_id
		event_id:         event_id
		effect_id:        e.effect_type().id
		amplifier:        e.level() - 1
		particles:        !e.particles_hidden()
		duration:         e.duration_ticks()
		tick:             u64(e.tick())
		ambient:          e.ambient()
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

fn (mut s NetworkSession) apply_effect_tick(e effect.Effect) {
	match e.effect_type().id {
		effect.instant_health.id {
			amount := f32((2 << e.level())) * f32(e.potency())
			s.heal(amount)
		}
		effect.instant_damage.id {
			amount := f32((3 << e.level())) * f32(e.potency())
			s.damage_from_effect(amount, true)
		}
		effect.regeneration.id {
			interval := math.max(50 >> (e.level() - 1), 1)
			if e.tick() % interval == 0 {
				s.heal(1)
			}
		}
		effect.poison.id {
			interval := math.max(50 >> (e.level() - 1), 1)
			if e.tick() % interval == 0 && s.health > 1 {
				s.damage_from_effect(1, false)
			}
		}
		effect.wither.id, effect.fatal_poison.id {
			interval := math.max(80 >> e.level(), 1)
			if e.tick() % interval == 0 {
				s.damage_from_effect(1, true)
			}
		}
		else {}
	}
}

fn (mut s NetworkSession) heal(amount f32) {
	if s.dead || amount <= 0 {
		return
	}
	old := s.health
	s.health += amount
	if s.health > 20 {
		s.health = 20
	}
	if s.health != old {
		s.send_health()
	}
}

fn (mut s NetworkSession) damage_from_effect(amount f32, fatal bool) {
	if s.dead || amount <= 0 || s.game_mode == protocol.game_type_creative
		|| s.game_mode == protocol.game_type_spectator {
		return
	}
	if !fatal && s.health - amount < 1 {
		s.health = 1
	} else {
		s.health -= amount
	}
	if s.health < 0 {
		s.health = 0
	}
	s.send_health()
	if s.spawned {
		s.hub.broadcast(&protocol.ActorEventPacket{
			actor_runtime_id: s.runtime_id
			event_id:         protocol.actor_event_hurt
			event_data:       0
		})
	}
	if s.health <= 0 {
		s.die('%death.attack.magic', [s.identity.display_name])
	}
}

fn (mut s NetworkSession) send_health() {
	if !s.spawned {
		return
	}
	s.transport.send(s.health_update()) or {}
}
