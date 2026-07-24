module entity

import protocol
import server.effect
import server.item

// LingeringCloudBehaviour is an entity that hovers at the impact point of a
// lingering potion.  It is non-solid, unaffected by gravity, and applies
// reduced-duration potion effects to every actor inside its radius.
// The radius shrinks over time (linear decay) and on each application to an
// entity.  When the radius reaches zero the cloud dissipates.
// https://minecraft.fandom.com/fr/wiki/Potion_%C3%A0_effet_persistant
@[heap]
pub struct LingeringCloudBehaviour {
pub:
	network_id string = 'minecraft:lingering_potion'
	meta       int // potion type, same as drinkable/splash
pub mut:
	// Initial radius: 3 blocks.  Lasts 30 s (600 ticks), linear decay to 0.
	// 3.0 / 600 = 0.005 per tick.
	radius         f32 = 3.0
	duration_ticks int = 600
	// Wait 0.5 s (10 ticks) before the cloud becomes active.
	activation_delay int = 10
	// Don't reapply to the same entity within 20 ticks (1 s).
	reapply_delay int = 20
	// Radius shrinks by this amount per entity application.
	radius_per_apply f32 = 0.05
	// Radius shrinks by this amount per tick (linear decay).
	radius_per_tick f32 = 0.005
	// Per-entity reapplication cooldown: maps runtime_id -> next tick when
	// the entity can receive another application.
	cooldowns map[u64]i64
}

pub fn (b &LingeringCloudBehaviour) identifier() string {
	return b.network_id
}

pub fn (mut b LingeringCloudBehaviour) tick(mut e Entity, mut host Host) {
	// Cloud doesn't move — no gravity, no physics.
	e.no_gravity = true

	if e.age < b.activation_delay {
		return
	}

	b.duration_ticks--
	if b.duration_ticks <= 0 || b.radius <= 0.01 {
		e.kill()
		return
	}

	effects := item.potion_from_meta(b.meta).effects()
	colour := blend_splash_colour(effects)

	// Get all actors inside the current radius and apply reduced effects.
	targets := host.entities_near(e.pos, b.radius)
	current_tick := e.age

	for rid in targets {
		// Reapplication cooldown: skip entities we just applied to.
		if next := b.cooldowns[rid] {
			if current_tick < next {
				continue
			}
		}
		b.cooldowns[rid] = current_tick + b.reapply_delay

		// Apply lingering effects: duration is 1/4 of the drinkable
		// version.  Instant effects also get reduced potency.
		// https://minecraft.fandom.com/fr/wiki/Potion_%C3%A0_effet_persistant
		for ef in effects {
			mut cloud_ef := ef

			if cloud_ef.instant() {
				// Instant effects: potency is halved for lingering.
				if host.is_undead(rid) {
					cloud_ef = invert_undead_instant(cloud_ef)
				}
				cloud_ef = effect.new_instant_with_potency(cloud_ef.effect_type(),
					cloud_ef.level(), cloud_ef.potency() * 0.5)
			} else if !cloud_ef.infinite() {
				// Duration effects: 1/4 of the drinkable duration.
				quarter := cloud_ef.duration_ticks() / 4
				if quarter < 1 {
					continue
				}
				cloud_ef = effect.new_with_ticks(cloud_ef.effect_type(), cloud_ef.level(), quarter)
			}
			host.add_effect_to(rid, cloud_ef)
		}

		// Each application shrinks the cloud radius.
		b.radius -= b.radius_per_apply
	}

	// Linear radius decay over time.
	b.radius -= b.radius_per_tick
	if b.radius <= 0.01 {
		b.radius = 0.01
		e.kill()
		return
	}

	// Particles: spawn coloured splash particles inside the cloud volume.
	// https://minecraft.fandom.com/fr/wiki/Potion_%C3%A0_effet_persistant
	host.broadcast_near(e.pos.x, e.pos.y, e.pos.z, b.radius * 2, &protocol.LevelEventPacket{
		event_id:   level_event_potion_splash
		position:   e.pos
		event_data: colour
	})
}
