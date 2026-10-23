module session

import bedrock_v.protocol
import bedrock_v.protocol.types
import bedrock_v.protocol.model
import server.effect
import server.player
import server.worldrt
import bedrock_v.protocol.enums
import bedrock_v.protocol.packets

// NetworkSession is how a player.Viewer event reaches a real client: each
// method turns one thing that happened into the packets this particular client
// needs in order to see it.
//
// The player something happened to is a viewer like any other, so every method
// that has to tell them apart does it by comparing runtime ids rather than by
// being called differently. That check is the whole reason the split between
// "my own client" and "everyone else" does not belong in the verb.

// is_self reports whether "p"layer is the player this session drives.
fn (s &NetworkSession) is_self(p &player.Player) bool {
	return p.runtime_id() == s.runtime_id
}

fn (mut s NetworkSession) view_teleport(p &player.Player, pos model.Vector3) {
	if !s.is_self(p) {
		s.deliver(s.move_actor_packet(p))
		return
	}

	current := p.movement()
	mut move_packet := &packets.MovePlayerPacket{
		player_runtime_id: protocol.actor_runtime_id(self_entity_runtime_id)
		y_head_rotation:   current.head_yaw
		position_mode:     enums.PlayerPositionMode.teleport
		teleport_data:     types.MovePlayerTeleportData{}
		on_ground:         false
	}
	move_packet.position[0] = pos.x
	move_packet.position[1] = pos.y
	move_packet.position[2] = pos.z
	move_packet.rotation[0] = current.pitch
	move_packet.rotation[1] = current.yaw
	s.deliver(move_packet)
	s.expect_teleport_ack(pos)
}

// A move the client reported itself needs no answer, so only the other
// clients in the world are told.
fn (mut s NetworkSession) view_movement(p &player.Player) {
	if s.is_self(p) {
		return
	}
	s.deliver(s.move_actor_packet(p))
}

fn (mut s NetworkSession) view_hurt(p &player.Player) {
	s.deliver(&packets.ActorEventPacket{
		target_runtime_id: protocol.actor_runtime_id(s.wire_id_for(p.runtime_id()))
		event_id:          enums.ActorEvent.hurt
		data:              0
	})
}

fn (mut s NetworkSession) view_death(p &player.Player, message_key string, parameters []string) {
	if !s.is_self(p) {
		s.deliver(&packets.ActorEventPacket{
			target_runtime_id: protocol.actor_runtime_id(s.wire_id_for(p.runtime_id()))
			event_id:          enums.ActorEvent.death
			data:              0
		})
	}
	s.deliver(&packets.TextPacket{
		localize:     true
		message_type: enums.TextTranslate{
			message:        message_key
			parameter_list: parameters
		}
	})
}

fn (mut s NetworkSession) view_effect_added(p &player.Player, e effect.Effect) {
	s.deliver(&packets.MobEffectPacket{
		target_runtime_id: protocol.actor_runtime_id(s.wire_id_for(p.runtime_id()))
		event_id:          packets.MobEffectEvent.remove
		effect_id:         e.effect_type().id
	})
	s.deliver(s.mob_effect_packet(p, e, packets.MobEffectEvent.add))
}

fn (mut s NetworkSession) view_effect_removed(p &player.Player, typ effect.Type) {
	s.deliver(&packets.MobEffectPacket{
		target_runtime_id: protocol.actor_runtime_id(s.wire_id_for(p.runtime_id()))
		event_id:          packets.MobEffectEvent.remove
		effect_id:         typ.id
	})
}

// viewers_of returns the player viewers in tx's world and viewers_except the
// same minus one actor. Every "show this to everyone else" site goes through
// them so the skip is written once.
fn viewers_of(mut tx worldrt.WorldTx) []player.Viewer {
	mut out := []player.Viewer{}
	for mut v in tx.wr.viewers() {
		if mut v is player.Viewer {
			out << v
		}
	}
	return out
}

fn viewers_except(mut tx worldrt.WorldTx, actor u64) []player.Viewer {
	mut out := []player.Viewer{}
	for mut v in tx.wr.viewers() {
		if v.runtime_id() == actor {
			continue
		}
		if mut v is player.Viewer {
			out << v
		}
	}
	return out
}

fn (mut s NetworkSession) view_player_added(p &player.Player) {
	s.deliver(s.player_list_add_packet(p))
	s.deliver(s.add_player_packet(p))
}

fn (mut s NetworkSession) view_player_removed(p &player.Player) {
	s.deliver(s.remove_actor_packet(p))
	s.deliver(s.player_list_remove_packet(p))
}

fn (mut s NetworkSession) view_player_respawned(p &player.Player) {
	s.deliver(s.remove_actor_packet(p))
	s.deliver(s.add_player_packet(p))
}

fn (mut s NetworkSession) view_equipment(p &player.Player, hotbar_slot int, inventory_slot int, item model.ItemStackWrapper) {
	s.deliver(&packets.MobEquipmentPacket{
		target_runtime_id: protocol.actor_runtime_id(s.wire_id_for(p.runtime_id()))
		item:              protocol.item_descriptor_v2(item.item_stack)
		slot:              i8(inventory_slot)
		selected_slot:     i8(hotbar_slot)
		container_id:      .inventory
	})
}

fn (mut s NetworkSession) view_air_supply(p &player.Player, air i64) {
	s.deliver(&packets.SetActorDataPacket{
		target_runtime_id: protocol.actor_runtime_id(s.wire_id_for(p.runtime_id()))
		actor_data:        [
			types.DataItem{
				data_item_id:   protocol.meta_key_air_supply
				data_item_type: types.DataItemShort{
					value: i16(air)
				}
			},
			types.DataItem{
				data_item_id:   protocol.meta_key_air_supply_max
				data_item_type: types.DataItemShort{
					value: i16(player.max_air_supply_ticks)
				}
			},
		]
		synced_properties: types.PropertySyncData{}
		tick:              0
	})
}

// The three below name an actor by its internal id: what happened is the same
// whether a player or a mob did it.

fn (mut s NetworkSession) view_actor_swing(actor u64) {
	s.deliver(&packets.AnimatePacket{
		action:            packets.AnimatePacketAction.swing
		target_runtime_id: protocol.actor_runtime_id(s.wire_id_for(actor))
	})
}

fn (mut s NetworkSession) view_actor_critical_hit(actor u64) {
	s.deliver(&packets.AnimatePacket{
		action:            packets.AnimatePacketAction.critical_hit
		target_runtime_id: protocol.actor_runtime_id(s.wire_id_for(actor))
	})
}

fn (mut s NetworkSession) view_item_taken(item u64, taker u64) {
	s.deliver(&packets.TakeItemActorPacket{
		item_runtime_id:  protocol.actor_runtime_id(s.wire_id_for(item))
		actor_runtime_id: protocol.actor_runtime_id(s.wire_id_for(taker))
	})
}
