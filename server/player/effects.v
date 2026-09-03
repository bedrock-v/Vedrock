module player

import math
import bedrock_v.protocol.current as proto
import server.effect
import server.event
import server.worldrt

const mob_effect_add = proto.MobEffectEvent.add
const mob_effect_remove = proto.MobEffectEvent.remove

// The player's status effects.
//
// Applying, removing and ticking an effect takes the transaction: each one
// dispatches an event, may damage or kill the player, and shows the result to
// everyone in the world, all of which the owning actor owns. The send_ helpers
// take the runtime instead because they only broadcast and the login path
// sends a joining player's effects from the session thread.

// add_effect applies "e"ffect to the player. Cancelling EffectAddData rejects the
// effect outright. An instant effect (one that is applied and not stored)
// takes hold immediately; a lasting one waits for the next tick.
pub fn (mut p Player) add_effect(mut tx worldrt.WorldTx, e effect.Effect) {
	mut ctx := event.new_context(EffectAddData{
		effect_name:    e.effect_type().name
		level:          e.level()
		duration_ticks: e.duration_ticks()
		player:         p
	})
	p.handler.on_effect_add(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	result := p.add_effect_result(e)
	if result.accepted {
		if result.replaced {
			p.apply_effect_end(result.previous)
		}
		p.apply_effect_start(result.effect)
		if !result.stored {
			p.apply_effect_tick(mut tx, result.effect)
		}
	}
	p.send_effect(mut tx.wr, result.effect)
}

// remove_effect strips typ from the player early, before it would have run
// out. Cancelling EffectRemoveData keeps it active.
pub fn (mut p Player) remove_effect(mut tx worldrt.WorldTx, typ effect.Type) {
	mut ctx := event.new_context(EffectRemoveData{
		effect_name: typ.name
		player:      p
	})
	p.handler.on_effect_remove(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	removed := p.take_effect(typ) or { return }
	p.apply_effect_end(removed)
	p.send_effect_removal(mut tx.wr, typ)
}

// tick_effects advances the player's active effects one tick during the owning
// world's simulation step, applying what each still running effect does and
// clearing the ones that ran out.
pub fn (mut p Player) tick_effects(mut tx worldrt.WorldTx) {
	result := p.advance_effects()
	for e in result.active {
		p.apply_effect_tick(mut tx, e)
	}
	for e in result.expired {
		p.apply_effect_end(e)
		p.send_effect_removal(mut tx.wr, e.effect_type())
	}
}

// send_active_effects replays every effect the player is already under, for a
// client that has just arrived and knows about none of them.
pub fn (mut p Player) send_active_effects(mut wr worldrt.WorldRuntime) {
	for e in p.active_effects() {
		p.send_effect(mut wr, e)
	}
}

// send_effect shows e on the player. The removal first clears whatever the
// clients are already drawing for that effect, so a refreshed duration or a
// raised level replaces the old one rather than stacking with it.
pub fn (mut p Player) send_effect(mut wr worldrt.WorldRuntime, e effect.Effect) {
	p.send_effect_removal(mut wr, e.effect_type())
	p.send_mob_effect(mut wr, e, mob_effect_add)
}

// Effect packets are visible only to players in the same world.
pub fn (mut p Player) send_effect_removal(mut wr worldrt.WorldRuntime, typ effect.Type) {
	mut sink := p.sink
	if !sink.is_spawned() {
		return
	}
	wr.broadcast_world(&proto.MobEffectPacket{
		target_runtime_id: proto.actor_runtime_id(sink.runtime_id())
		event_id:          mob_effect_remove
		effect_id:         typ.id
	})
}

pub fn (mut p Player) send_mob_effect(mut wr worldrt.WorldRuntime, e effect.Effect, event_id proto.MobEffectEvent) {
	mut sink := p.sink
	if !sink.is_spawned() {
		return
	}
	wr.broadcast_world(p.mob_effect_packet(e, event_id))
}

// mob_effect_packet is one effect as the other clients in the world see it.
pub fn (p &Player) mob_effect_packet(e effect.Effect, event_id proto.MobEffectEvent) &proto.MobEffectPacket {
	mut sink := p.sink
	return &proto.MobEffectPacket{
		target_runtime_id:     proto.actor_runtime_id(sink.runtime_id())
		event_id:              event_id
		effect_id:             e.effect_type().id
		effect_amplifier:      e.level() - 1
		show_particles:        !e.particles_hidden()
		effect_duration_ticks: e.duration_ticks()
		tick:                  u64(e.tick())
		ambient:               e.ambient()
	}
}

// apply_effect_start/apply_effect_end are what an effect does on the way in and
// on the way out, as opposed to once per tick. Absorption changes the health
// bar's size rather than its value, so the client needs it resent either way.
fn (mut p Player) apply_effect_start(e effect.Effect) {
	match e.effect_type().id {
		effect.absorption.id {
			p.send_health()
		}
		else {}
	}
}

fn (mut p Player) apply_effect_end(e effect.Effect) {
	match e.effect_type().id {
		effect.absorption.id {
			p.send_health()
		}
		else {}
	}
}

// apply_effect_tick is one tick's worth of a lasting effect or the whole of
// an instant one. The overtime effects fire on an interval that halves with
// each level, down to a floor of every tick.
fn (mut p Player) apply_effect_tick(mut tx worldrt.WorldTx, e effect.Effect) {
	match e.effect_type().id {
		effect.instant_health.id {
			amount := f32((2 << e.level())) * f32(e.potency())
			p.heal(amount)
		}
		effect.instant_damage.id {
			amount := f32((3 << e.level())) * f32(e.potency())
			p.damage_from_effect(mut tx, amount, true)
		}
		effect.regeneration.id {
			interval := math.max(50 >> (e.level() - 1), 1)
			if e.tick() % interval == 0 {
				p.heal(1)
			}
		}
		effect.poison.id {
			interval := math.max(50 >> (e.level() - 1), 1)
			if e.tick() % interval == 0 && p.health() > 1 {
				p.damage_from_effect(mut tx, 1, false)
			}
		}
		effect.wither.id, effect.fatal_poison.id {
			interval := math.max(80 >> e.level(), 1)
			if e.tick() % interval == 0 {
				p.damage_from_effect(mut tx, 1, true)
			}
		}
		else {}
	}
}

// damage_from_effect handles damage caused by effects. Poison style non-fatal
// damage floors at one health; fatal effects may kill and go through die so
// all deaths share one path. Effect damage has no attacker, it dispatches
// no hurt event and reports the same death message the combat path's magic
// damage source does.
fn (mut p Player) damage_from_effect(mut tx worldrt.WorldTx, amount f32, fatal bool) {
	if p.is_dead() || amount <= 0 || !p.game_mode().allows_taking_damage() {
		return
	}
	if !fatal && p.health() - amount < 1 {
		p.set_health(1)
	} else {
		p.set_health(p.health() - amount)
	}
	if p.health() < 0 {
		p.set_health(0)
	}
	p.send_health()
	mut sink := p.sink
	if sink.is_spawned() {
		tx.wr.broadcast_world(&proto.ActorEventPacket{
			target_runtime_id: proto.actor_runtime_id(sink.runtime_id())
			event_id:          proto.ActorEvent.hurt
			data:              0
		})
	}
	if p.health() <= 0 {
		p.die(mut tx, '%death.attack.magic', [p.identity.display_name])
	}
}
