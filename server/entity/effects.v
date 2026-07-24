module entity

import protocol
import protocol.types
import server.effect

const mob_effect_add = 1
const mob_effect_remove = 3

// add_effect stores ef on e and syncs it to viewers.
pub fn (mut e Entity) add_effect(mut host Host, ef effect.Effect) {
	result := e.effects.add_result(ef)
	if !result.accepted {
		return
	}
	if !result.stored {
		e.apply_effect_tick(mut host, result.effect)
	}
	e.update_effect_metadata(mut host)
	host.broadcast(e.mob_effect_packet(result.effect, mob_effect_add))
}

// remove_effect strips typ from e, if present, and tells viewers.
pub fn (mut e Entity) remove_effect(mut host Host, typ effect.Type) {
	e.effects.remove(typ) or { return }
	host.broadcast(&protocol.MobEffectPacket{
		actor_runtime_id: e.runtime_id
		event_id:         mob_effect_remove
		effect_id:        typ.id
	})
	e.update_effect_metadata(mut host)
}

// active_effects lists every effect currently active on e.
pub fn (e &Entity) active_effects() []effect.Effect {
	return e.effects.effects()
}

// tick_effects advances e's effect durations one tick, applying any per-tick
// damage/heal and telling viewers when one expires.
fn (mut e Entity) tick_effects(mut host Host) {
	result := e.effects.tick()
	for ef in result.active {
		e.apply_effect_tick(mut host, ef)
	}
	for ef in result.expired {
		host.broadcast(&protocol.MobEffectPacket{
			actor_runtime_id: e.runtime_id
			event_id:         mob_effect_remove
			effect_id:        ef.effect_type().id
		})
	}
	if result.expired.len > 0 {
		e.update_effect_metadata(mut host)
	}
}

fn (e &Entity) mob_effect_packet(ef effect.Effect, event_id int) &protocol.MobEffectPacket {
	return &protocol.MobEffectPacket{
		actor_runtime_id: e.runtime_id
		event_id:         event_id
		effect_id:        ef.effect_type().id
		amplifier:        ef.level() - 1
		particles:        !ef.particles_hidden()
		duration:         ef.duration_ticks()
		tick:             u64(ef.tick())
		ambient:          ef.ambient()
	}
}

// apply_effect_tick applies one tick's worth of a lasting effect's
// damage or healing.
fn (mut e Entity) apply_effect_tick(mut host Host, ef effect.Effect) {
	match ef.effect_type().id {
		effect.instant_health.id {
			e.heal(f32(2 << ef.level()) * f32(ef.potency()))
		}
		effect.instant_damage.id {
			e.hurt(mut host, f32(3 << ef.level()) * f32(ef.potency()), true, 0)
		}
		effect.regeneration.id {
			interval := effect_tick_interval(50, ef.level(), true)
			if ef.tick() % interval == 0 {
				e.heal(1)
			}
		}
		effect.poison.id {
			interval := effect_tick_interval(50, ef.level(), true)
			if ef.tick() % interval == 0 && e.health > 1 {
				e.hurt(mut host, 1, false, 0)
			}
		}
		effect.wither.id, effect.fatal_poison.id {
			interval := effect_tick_interval(80, ef.level(), false)
			if ef.tick() % interval == 0 {
				e.hurt(mut host, 1, true, 0)
			}
		}
		else {}
	}
}

fn effect_tick_interval(base int, level int, level_minus_one bool) int {
	shift := if level_minus_one { level - 1 } else { level }
	interval := base >> shift
	return if interval > 1 { interval } else { 1 }
}

// update_effect_metadata recalculates the blended potion particle colour from all
// active effects on e and broadcasts it as entity metadata so viewers see the
// correct swirling particles.
fn (e &Entity) update_effect_metadata(mut host Host) {
	active := e.effects.effects()
	colour := effect.blend_colour(active)
	ambient := effect.any_ambient(active)
	mut ambient_byte := u8(0)
	if ambient {
		ambient_byte = 1
	}
	host.broadcast(&protocol.SetActorDataPacket{
		actor_runtime_id:  e.runtime_id
		metadata:          [
			types.MetadataEntry{
				key:   protocol.meta_key_effect_color
				value: types.MetaInt{
					value: colour
				}
			},
			types.MetadataEntry{
				key:   protocol.meta_key_effect_ambience
				value: types.MetaByte{
					value: i8(ambient_byte)
				}
			},
		]
		synced_properties: types.PropertySyncData{}
		tick:              0
	})
}

// mobspell_molang_json builds the Molang variable JSON for the mobspell_emitter
// particle colour. Format: array of {name, value} with float RGB in [0,1].
