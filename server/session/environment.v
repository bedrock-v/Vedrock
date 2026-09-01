module session

import math
import server.player
import server.world
import bedrock_v.protocol.current as proto
import server.worldrt

// Environmental damage uses per source tick intervals to approximate repeat
// damage. These intervals replace general invincibility frames which we
// don't currently implement.
const void_damage_amount = f32(4.0)
const void_damage_interval_ticks = i64(10)
const void_damage_y = f32(world.dimension_min_y - 4)

const drowning_damage_amount = f32(2.0)
const drowning_damage_interval_ticks = i64(20) // once per second once air runs out

const lava_contact_damage = f32(4.0)
const lava_fire_ticks = i64(15 * 20) // 15 seconds
const fire_tick_damage = f32(1.0)
const fire_tick_interval_ticks = i64(20) // once per second while burning

// tick_environmental_damage applies void, drowning and fire/lava damage for
// one player during the owning world's simulation step.
fn (mut s NetworkSession) tick_environmental_damage(mut tx worldrt.WorldTx) {
	if s.player.is_dead() || !s.player.game_mode().allows_taking_damage() {
		return
	}
	tick := tx.wr.services.current_tick()
	pos := s.current_position()

	if pos.y < void_damage_y {
		if tick % void_damage_interval_ticks == 0 {
			s.apply_hurt(mut tx.wr, void_damage_amount, VoidDamageSource{})
		}
	}

	block_id := block_at(tx, int(math.floor(pos.x)), int(math.floor(pos.y)), int(math.floor(pos.z)))
	s.tick_breath(mut tx, block_id == world.water.network_id, tick)
	s.tick_burning(mut tx, block_id == world.lava.network_id, block_id == world.water.network_id)
}

// tick_breath drains or refills the underwater breath meter and applies
// drowning damage once it runs out.
fn (mut s NetworkSession) tick_breath(mut tx worldrt.WorldTx, submerged bool, tick i64) {
	old_air := s.player.air_supply()
	mut air := old_air
	if submerged {
		if air > 0 {
			air--
			s.player.set_air_supply(air)
		} else if tick % drowning_damage_interval_ticks == 0 {
			s.apply_hurt(mut tx.wr, drowning_damage_amount, DrowningDamageSource{})
		}
	} else if air < player.max_air_supply_ticks {
		air = player.max_air_supply_ticks
		s.player.set_air_supply(air)
	}
	if air != old_air {
		s.send_air_supply(mut tx.wr, air)
	}
}

// tick_burning handles lava contact and the ongoing once-per-second fire
// damage while burning, extinguishing on contact with water.
fn (mut s NetworkSession) tick_burning(mut tx worldrt.WorldTx, in_lava bool, in_water bool) {
	if in_water {
		if s.player.fire_ticks() > 0 {
			s.player.set_fire_ticks(0)
		}
		return
	}
	if in_lava {
		if s.player.fire_ticks() <= 0 {
			s.apply_hurt(mut tx.wr, lava_contact_damage, LavaDamageSource{})
		}
		s.player.set_fire_ticks(lava_fire_ticks)
		return
	}
	remaining := s.player.fire_ticks()
	if remaining <= 0 {
		return
	}
	next := remaining - 1
	s.player.set_fire_ticks(next)
	if next > 0 && next % fire_tick_interval_ticks == 0 {
		s.apply_hurt(mut tx.wr, fire_tick_damage, FireDamageSource{})
	}
}

fn (mut s NetworkSession) send_air_supply(mut wr worldrt.WorldRuntime, air i64) {
	if !s.spawned {
		return
	}
	wr.broadcast_world(&proto.SetActorDataPacket{
		target_runtime_id: proto.actor_runtime_id(s.runtime_id)
		actor_data:        [
			proto.DataItem{
				data_item_id:   proto.meta_key_air_supply
				data_item_type: proto.DataItemShort{
					value: i16(air)
				}
			},
			proto.DataItem{
				data_item_id:   proto.meta_key_air_supply_max
				data_item_type: proto.DataItemShort{
					value: i16(player.max_air_supply_ticks)
				}
			},
		]
		synced_properties: proto.PropertySyncData{}
		tick:              0
	})
}
