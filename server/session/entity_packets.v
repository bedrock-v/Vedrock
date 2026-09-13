module session

import bedrock_v.protocol
import bedrock_v.protocol.current as proto
import server.effect
import server.entity
import bedrock_v.protocol.version.v2168.enums as enums_2168
import bedrock_v.protocol.version.v975.enums as enums_975
import bedrock_v.protocol.version.v2168.packets as packets_2168
import bedrock_v.protocol.version.v662.packets as packets_662
import bedrock_v.protocol.version.v729.packets as packets_729
import bedrock_v.protocol.version.v898.packets as packets_898
import bedrock_v.protocol.version.v975.packets as packets_975
import bedrock_v.protocol.version.v2168.types as types_2168
import bedrock_v.protocol.version.v662.types as types_662
import bedrock_v.protocol.version.v712.types as types_712

fn entity_metadata_entries(e &entity.Entity) []types_2168.DataItem {
	mut flags := i64(0)
	if e.dimensions.has_collision {
		flags |= entity_flag_bit(proto.entity_flag_has_collision)
	}
	if !e.no_gravity {
		flags |= entity_flag_bit(proto.entity_flag_affected_by_gravity)
	}
	return [
		types_2168.DataItem{
			data_item_id:   proto.meta_key_flags
			data_item_type: enums_2168.DataItemInt64{
				value: flags
			}
		},
		types_2168.DataItem{
			// Every actor needs an explicit scale or a real client has
			// nothing to size the model by.
			data_item_id:   proto.meta_key_scale
			data_item_type: enums_2168.DataItemFloat{
				value: f32(1.0)
			}
		},
		types_2168.DataItem{
			data_item_id:   proto.meta_key_width
			data_item_type: enums_2168.DataItemFloat{
				value: e.dimensions.width
			}
		},
		types_2168.DataItem{
			data_item_id:   proto.meta_key_height
			data_item_type: enums_2168.DataItemFloat{
				value: e.dimensions.height
			}
		},
	]
}

// entity_attribute_entries is the health attribute a client needs at spawn.
fn entity_attribute_entries(e &entity.Entity) []packets_2168.AttributeEntry {
	return [
		packets_2168.AttributeEntry{
			attribute_name: 'minecraft:health'
			min_value:      0.0
			current_value:  e.health
			max_value:      entity.mob_max_health
		},
	]
}

// entity_spawn_packet puts "e"ntity into a client's world. An item on the ground is a
// different packet from everything else.
fn (mut s NetworkSession) entity_spawn_packet(e &entity.Entity) protocol.Packet {
	if e.behaviour is entity.ItemBehaviour {
		item_stack := e.behaviour.stack
		mut packet := &packets_2168.AddItemActorPacket{
			target_actor_id:   proto.actor_unique_id(i64(s.wire_id_for(e.runtime_id)))
			target_runtime_id: proto.actor_runtime_id(s.wire_id_for(e.runtime_id))
			item:              proto.item_descriptor(item_stack)
			entity_data:       entity_metadata_entries(e)
			from_fishing:      false
		}
		packet.position[0] = e.pos.x
		packet.position[1] = e.pos.y
		packet.position[2] = e.pos.z
		packet.velocity[0] = e.velocity.x
		packet.velocity[1] = e.velocity.y
		packet.velocity[2] = e.velocity.z
		return packet
	}
	mut packet := &packets_2168.AddActorPacket{
		target_actor_id:   proto.actor_unique_id(i64(s.wire_id_for(e.runtime_id)))
		target_runtime_id: proto.actor_runtime_id(s.wire_id_for(e.runtime_id))
		actor_type:        e.identifier
		y_head_rotation:   e.head_yaw
		y_body_rotation:   e.yaw
		attributes:        entity_attribute_entries(e)
		actor_data:        entity_metadata_entries(e)
		synced_properties: types_662.PropertySyncData{}
		actor_links:       []types_712.ActorLink{}
	}
	packet.position[0] = e.pos.x
	packet.position[1] = e.pos.y
	packet.position[2] = e.pos.z
	packet.velocity[0] = e.velocity.x
	packet.velocity[1] = e.velocity.y
	packet.velocity[2] = e.velocity.z
	packet.rotation[0] = e.pitch
	packet.rotation[1] = e.yaw
	return packet
}

fn (mut s NetworkSession) entity_despawn_packet(e &entity.Entity) &packets_662.RemoveActorPacket {
	return &packets_662.RemoveActorPacket{
		target_actor_id: proto.actor_unique_id(i64(s.wire_id_for(e.runtime_id)))
	}
}

fn (mut s NetworkSession) entity_move_packet(e &entity.Entity) &packets_662.MoveActorAbsolutePacket {
	return &packets_662.MoveActorAbsolutePacket{
		move_data: types_662.MoveActorAbsoluteData{
			actor_runtime_id: proto.actor_runtime_id(s.wire_id_for(e.runtime_id))
			header:           i8(proto.move_actor_flag_on_ground)
			position_x:       e.pos.x
			position_y:       e.pos.y
			position_z:       e.pos.z
			rotation_x:       proto.rotation_byte(e.pitch)
			rotation_y:       proto.rotation_byte(e.yaw)
			rotation_y_head:  proto.rotation_byte(e.head_yaw)
		}
	}
}

// entity_health_update_packet reports the current health so a client watching
// this entity's bar sees the new value.
fn (mut s NetworkSession) entity_health_update_packet(e &entity.Entity) &packets_729.UpdateAttributesPacket {
	return &packets_729.UpdateAttributesPacket{
		target_runtime_id:       proto.actor_runtime_id(s.wire_id_for(e.runtime_id))
		attribute_list:          [
			packets_729.AttributeData{
				min_value:           0.0
				max_value:           entity.mob_max_health
				current_value:       e.health
				default_min:         0.0
				default_max:         entity.mob_max_health
				default_value:       entity.mob_max_health
				attribute_name:      'minecraft:health'
				attribute_modifiers: []packets_729.AttributeModifier{}
			},
		]
		ticks_since_sim_started: 0
	}
}

fn (mut s NetworkSession) entity_mob_effect_packet(e &entity.Entity, ef effect.Effect, event_id packets_898.MobEffectEvent) &packets_898.MobEffectPacket {
	return &packets_898.MobEffectPacket{
		target_runtime_id:     proto.actor_runtime_id(s.wire_id_for(e.runtime_id))
		event_id:              event_id
		effect_id:             ef.effect_type().id
		effect_amplifier:      ef.level() - 1
		show_particles:        !ef.particles_hidden()
		effect_duration_ticks: ef.duration_ticks()
		tick:                  u64(ef.tick())
		ambient:               ef.ambient()
	}
}

// NetworkSession as an entity.Viewer. Same idea as viewer.v for players: the
// entity reports what happened, this turns it into what a client is sent.

fn (mut s NetworkSession) view_entity_spawn(e &entity.Entity) {
	s.deliver(s.entity_spawn_packet(e))
}

fn (mut s NetworkSession) view_entity_despawn(e &entity.Entity) {
	s.deliver(s.entity_despawn_packet(e))
}

fn (mut s NetworkSession) view_entity_movement(e &entity.Entity) {
	s.deliver(s.entity_move_packet(e))
}

fn (mut s NetworkSession) view_entity_health(e &entity.Entity) {
	s.deliver(s.entity_health_update_packet(e))
}

fn (mut s NetworkSession) view_entity_hurt(e &entity.Entity) {
	s.deliver(&packets_975.ActorEventPacket{
		target_runtime_id: proto.actor_runtime_id(s.wire_id_for(e.runtime_id))
		event_id:          enums_975.ActorEvent.hurt
		data:              0
	})
}

// The removal first clears whatever the client is already drawing for that
// effect, so a refreshed duration or a raised level replaces the old one
// rather than stacking with it.
fn (mut s NetworkSession) view_entity_effect_added(e &entity.Entity, ef effect.Effect) {
	s.deliver(s.entity_mob_effect_packet(e, ef, packets_898.MobEffectEvent.add))
}

fn (mut s NetworkSession) view_entity_effect_removed(e &entity.Entity, typ effect.Type) {
	s.deliver(&packets_898.MobEffectPacket{
		target_runtime_id: proto.actor_runtime_id(s.wire_id_for(e.runtime_id))
		event_id:          packets_898.MobEffectEvent.remove
		effect_id:         typ.id
	})
}
