module entity

import math
import protocol
import server.effect
import server.item

// SplashPotionBehaviour is a projectile that applies potion effects to every
// actor within splash_radius on impact (entity or block). The meta field
// selects which potion type (use PotionType.effects() from server/item).
// https://minecraft.fandom.com/fr/wiki/Potion_jetable — radius 4.0 blocks.
@[heap]
pub struct SplashPotionBehaviour {
pub:
	network_id string = 'minecraft:splash_potion'
	meta       int // potion meta value (5-42), same as drinkable potions
pub mut:
	gravity_accel f32 = 0.05
	drag_factor   f32 = 0.01
	splash_radius f32 = 4.0
	stuck         bool
}

pub fn (b &SplashPotionBehaviour) identifier() string {
	return b.network_id
}

pub fn (mut b SplashPotionBehaviour) tick(mut e Entity, mut host Host) {
	if b.stuck {
		if e.age >= 100 {
			e.kill()
		}
		return
	}
	e.gravity_accel = b.gravity_accel
	e.drag_factor = b.drag_factor
	if e.age >= 200 {
		e.kill()
		return
	}
	if e.age <= 1 {
		return
	}
	// Check if we hit an entity.
	if _ := host.entity_hit_test(e.pos, e.runtime_id) {
		b.resolve_impact(mut e, mut host)
		e.kill()
		return
	}
	// Check if we hit a block.
	if e.hit_block {
		b.resolve_impact(mut e, mut host)
		e.kill()
		return
	}
}

// resolve_impact either applies splash effects immediately (splash
// potion) or spawns a lingering cloud entity (lingering potion).
fn (mut b SplashPotionBehaviour) resolve_impact(mut e Entity, mut host Host) {
	if b.network_id.contains('lingering') {
		// Lingering potion: spawn Area Effect Cloud that applies
		// reduced effects over time and broadcasts the impact sound.
		cloud := &LingeringCloudBehaviour{
			network_id: 'minecraft:lingering_potion'
			meta:       b.meta
		}
		host.spawn_behaviour(cloud, e.pos)
		// Glass break sound at impact (same as splash).
		host.broadcast_near(e.pos.x, e.pos.y, e.pos.z, 8.0, &protocol.LevelSoundEventPacket{
			sound:           'random.glass'
			position:        e.pos
			extra_data:      -1
			entity_type:     'minecraft:lingering_potion'
			actor_unique_id: e.unique_id
		})
	} else {
		// Splash potion: immediate area-of-effect.
		b.apply_splash(mut e, mut host)
	}
}

// apply_splash applies the potion effects to every actor within splash_radius
// and broadcasts the splash particle + glass-break sound.
fn (mut b SplashPotionBehaviour) apply_splash(mut e Entity, mut host Host) {
	effects := item.potion_from_meta(b.meta).effects()
	targets := host.entities_near(e.pos, b.splash_radius)
	// Blend ALL effects for the splash particle, including instant ones.
	// blend_colour skips non-lasting types (Healing/Harming have
	// lasting=false) so it would show a water splash for those.
	colour := blend_splash_colour(effects)

	// Apply effects to every actor in range with distance-based attenuation.
	// Duration scales linearly: max(0, 1 - distance/radius).
	// Instant effects (Healing/Harming) apply at full potency regardless of
	// distance; undead mobs invert them.
	// https://minecraft.fandom.com/fr/wiki/Potion_jetable
	for rid in targets {
		tp := host.entity_position(rid) or { continue }
		dx := tp.x - e.pos.x
		dy := tp.y - e.pos.y
		dz := tp.z - e.pos.z
		dist := math.sqrtf(dx * dx + dy * dy + dz * dz)

		for ef in effects {
			mut splash_ef := ef

			if splash_ef.instant() {
				// Instant effects: no duration scaling, but check
				// undead inversion — Healing damages undead and
				// vice versa.
				// https://minecraft.fandom.com/fr/wiki/Mort-vivant
				if host.is_undead(rid) {
					splash_ef = invert_undead_instant(splash_ef)
				}
			} else if !splash_ef.infinite() {
				// Duration scales linearly with distance from impact
				// centre: duration * (1 - distance/radius).
				scale := 1.0 - (dist / b.splash_radius)
				if scale <= 0 {
					continue
				}
				scaled := int(f32(splash_ef.duration_ticks()) * f32(scale))
				if scaled < 1 {
					continue
				}
				splash_ef = effect.new_with_ticks(splash_ef.effect_type(), splash_ef.level(),
					scaled)
			}
			host.add_effect_to(rid, splash_ef)
		}
	}

	// Splash particle event — the coloured cloud at the impact point.
	// LevelEvent ID 2002 is the Bedrock potion splash particle.
	host.broadcast_near(e.pos.x, e.pos.y, e.pos.z, b.splash_radius * 2, &protocol.LevelEventPacket{
		event_id:   level_event_potion_splash
		position:   e.pos
		event_data: colour
	})

	// Glass break sound at impact.
	// https://minecraft.fandom.com/fr/wiki/Potion_jetable
	host.broadcast_near(e.pos.x, e.pos.y, e.pos.z, b.splash_radius * 2, &protocol.LevelSoundEventPacket{
		sound:           'random.glass'
		position:        e.pos
		extra_data:      -1
		entity_type:     'minecraft:splash_potion'
		actor_unique_id: e.unique_id
	})
}

// invert_undead_instant swaps instant health and instant damage for undead
// targets. Instant Health (beneficial to living) damages undead; Instant Damage
// (harmful to living) heals undead.
// https://minecraft.fandom.com/fr/wiki/Mort-vivant
fn invert_undead_instant(ef effect.Effect) effect.Effect {
	if ef.effect_type().id == effect.instant_health.id {
		return effect.new_instant_with_potency(effect.instant_damage, ef.level(), ef.potency())
	}
	if ef.effect_type().id == effect.instant_damage.id {
		return effect.new_instant_with_potency(effect.instant_health, ef.level(), ef.potency())
	}
	return ef
}

// level_event_potion_splash is the Bedrock LevelEvent ID for the coloured
// splash potion particle cloud. Vanilla constant is 2002.

// blend_splash_colour averages the RGB colours of all effects (including
// instant ones) for the splash particle. Separate from effect.blend_colour
// which skips non-lasting types — those are needed for entity metadata
// particles but NOT for the impact splash, which should match the potion.
fn blend_splash_colour(effects []effect.Effect) int {
	if effects.len == 0 {
		return 0
	}
	mut r_sum, mut g_sum, mut b_sum := 0, 0, 0
	for ef in effects {
		t := ef.effect_type()
		r_sum += int(t.rgb[0])
		g_sum += int(t.rgb[1])
		b_sum += int(t.rgb[2])
	}
	count := effects.len
	// No alpha byte — LevelEvent 2002 expects 0x00RRGGBB, not 0xAARRGGBB.
	return int(u32(r_sum / count) << 16 | u32(g_sum / count) << 8 | u32(b_sum / count))
}

const level_event_potion_splash = 2002
