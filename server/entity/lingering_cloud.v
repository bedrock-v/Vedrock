module entity

import protocol
import protocol.types
import rand
import server.effect
import server.item

// LingeringCloudBehaviour is an Area Effect Cloud  -  the lingering cloud left
// behind when a lingering potion impacts. It hovers in place, is non-solid, and
// applies reduced-duration potion effects to every actor inside its radius.
// The radius shrinks linearly over time and on each entity application.
// When the radius reaches zero the cloud dissipates.
// https://minecraft.wiki/w/Lingering_Potion
@[heap]
pub struct LingeringCloudBehaviour {
pub:
	network_id string = 'minecraft:area_effect_cloud'
	meta       int // potion meta value, same as drinkable/splash
pub mut:
	radius           f32 = 3.0
	duration_ticks   int = 600   // 30 s at 20 TPS
	wait_time        int = 10    // 0.5 s before cloud activates
	reapply_delay    int = 40    // 2 s cooldown per entity
	radius_per_apply f32 = 0.5   // shrink on each entity application
	radius_per_tick  f32 = 0.005 // linear decay 3.0 -> 0 over 600 ticks
	cooldowns        map[u64]i64 // runtime_id -> next tick they can be reapplied
}

// cloud_meta_radius is Bedrock metadata key 61  -  AREA_EFFECT_CLOUD_RADIUS.
// Key 8 (meta_key_effect_color) is used for the particle colour instead of
// radius, so mobspell_emitter particles linked via actor_unique_id inherit
// the potion colour automatically.
const cloud_meta_radius = u32(61)
const cloud_meta_duration = u32(95)
const cloud_meta_radius_per_tick = u32(97)

pub fn (b &LingeringCloudBehaviour) identifier() string {
	return b.network_id
}

// spawn_packet builds the AddActorPacket for an area effect cloud. Sets
// effect colour at key 8 (so mobspell_emitter particles pick it up via
// actor_unique_id), radius at key 61, duration at 95, and decay at 97.
pub fn (b &LingeringCloudBehaviour) spawn_packet(e &Entity) &protocol.AddActorPacket {
	effects := item.potion_from_meta(b.meta).effects()
	colour := blend_splash_colour(effects)
	return &protocol.AddActorPacket{
		actor_unique_id:  e.unique_id
		actor_runtime_id: e.runtime_id
		type:             b.network_id
		position:         e.pos
		motion:           e.velocity
		pitch:            e.pitch
		yaw:              e.yaw
		head_yaw:         e.head_yaw
		body_yaw:         e.yaw
		attributes:        []types.ActorAttribute{}
		metadata:          [
			types.MetadataEntry{
				key:   cloud_meta_radius
				value: types.MetaFloat{value: b.radius}
			},
			types.MetadataEntry{
				key:   protocol.meta_key_effect_color
				value: types.MetaInt{value: colour}
			},
			types.MetadataEntry{
				key:   cloud_meta_duration
				value: types.MetaInt{value: b.duration_ticks}
			},
			types.MetadataEntry{
				key:   cloud_meta_radius_per_tick
				value: types.MetaFloat{value: -b.radius_per_tick}
			},
		]
		synced_properties: types.PropertySyncData{}
		links:             []types.EntityLink{}
	}
}

pub fn (mut b LingeringCloudBehaviour) tick(mut e Entity, mut host Host) {
	e.no_gravity = true
	effects := item.potion_from_meta(b.meta).effects()

	// Every tick: spawn a mobspell_emitter particle at actor_unique_id so
	// the client reads the colour from the entity's key-8 metadata. During
	// wait_time particles cluster at centre (radius is ignored by client
	// until Age hits wait_time); after, they distribute randomly across the
	// cloud volume.
	if b.wait_time > 0 {
		host.broadcast(&protocol.SpawnParticleEffectPacket{
			dimension_id:    0
			actor_unique_id: e.unique_id
			position:        types.Vector3{e.pos.x, e.pos.y + 0.05, e.pos.z}
			particle_name:   'minecraft:mobspell_emitter'
		})
	} else {
		ox := (rand.f32() * 2.0 - 1.0) * b.radius * 0.8
		oy := rand.f32() * 0.5
		oz := (rand.f32() * 2.0 - 1.0) * b.radius * 0.8
		host.broadcast(&protocol.SpawnParticleEffectPacket{
			dimension_id:    0
			actor_unique_id: e.unique_id
			position:        types.Vector3{e.pos.x + ox, e.pos.y + 0.1 + oy, e.pos.z + oz}
			particle_name:   'minecraft:mobspell_emitter'
		})
	}

	// During wait_time the cloud is visible but doesn't apply effects,
	// shrink, or decay.
	if b.wait_time > 0 {
		b.wait_time--
		b.duration_ticks--
		return
	}

	b.duration_ticks--
	if b.duration_ticks <= 0 {
		e.kill()
		return
	}

	// Only scan for targets and apply effects every 10 ticks  -  matches
	// vanilla Bedrock's area_effect_cloud application interval.
	// Skip when radius has shrunk to zero  -  the cloud persists until its
	// duration expires (vanilla: radius ≤ 0 makes the cloud invisible and
	// inert, it does not despawn the entity).
	if e.age % 10 == 0 && b.radius > 0.01 {
		b.prune_cooldowns(e.age)
		targets := host.entities_near(e.pos, b.radius)

		for rid in targets {
			if rid == e.runtime_id {
				continue
			}
			if rid in b.cooldowns {
				continue
			}
			b.cooldowns[rid] = e.age + b.reapply_delay

			for ef in effects {
				mut cloud_ef := ef

				if cloud_ef.instant() {
					if host.is_undead(rid) {
						cloud_ef = invert_undead_instant(cloud_ef)
					}
					cloud_ef = effect.new_instant_with_potency(cloud_ef.effect_type(),
						cloud_ef.level(), cloud_ef.potency() * 0.5)
				} else if !cloud_ef.infinite() {
					quarter := cloud_ef.duration_ticks() / 4
					if quarter < 1 {
						continue
					}
					cloud_ef = effect.new_with_ticks(cloud_ef.effect_type(), cloud_ef.level(), quarter)
				}
				host.add_effect_to(rid, cloud_ef)
			}

			b.radius -= b.radius_per_apply
			if b.radius < 0 {
				b.radius = 0
			}
		}
	}

	b.radius -= b.radius_per_tick
	if b.radius < 0 {
		b.radius = 0
	}

	host.broadcast_near(e.pos.x, e.pos.y, e.pos.z, view_radius, &protocol.SetActorDataPacket{
		actor_runtime_id: e.runtime_id
		metadata:         [
			types.MetadataEntry{
				key:   cloud_meta_radius
				value: types.MetaFloat{value: b.radius}
			},
		]
		synced_properties: types.PropertySyncData{}
	})
}

// prune_cooldowns removes expired cooldown entries so the map doesn't grow
// unbounded and stale entries don't block reapplication.
fn (mut b LingeringCloudBehaviour) prune_cooldowns(current_tick i64) {
	mut expired := []u64{}
	for rid, expiration in b.cooldowns {
		if current_tick >= expiration {
			expired << rid
		}
	}
	for rid in expired {
		b.cooldowns.delete(rid)
	}
}
