module player

import bedrock_v.protocol.current as proto
import bedrock_v.protocol.types
import server.event
import server.item
import server.worldrt

// The player's own actions.
//
// A verb speaks to its own client through the sink and to everyone else
// through a transaction. Both are built from the same state in the same actor
// turn and cannot disagree.
//
// A verb that reaches the world, or writes state the world actor owns, takes
// that world's transaction: it is how the verb gets there and the proof that
// it is running on the right thread since a transaction only exists inside a
// task. A verb that only speaks to its own client takes none because it
// needs neither.

// teleport moves the player to pos, tells its own client to snap there and
// shows the move to everyone else in the world.
pub fn (mut p Player) teleport(mut tx worldrt.WorldTx, pos types.Vector3) {
	p.reset_position(pos)
	current := p.movement()
	mut sink := p.sink
	rid := sink.runtime_id()

	mut move_packet := &proto.MovePlayerPacket{
		player_runtime_id: proto.actor_runtime_id(rid)
		y_head_rotation:   current.head_yaw
		position_mode:     proto.PlayerPositionMode.teleport
		teleport_data:     proto.MovePlayerTeleportData{}
		on_ground:         false
	}
	move_packet.position[0] = current.position.x
	move_packet.position[1] = current.position.y
	move_packet.position[2] = current.position.z
	move_packet.rotation[0] = current.pitch
	move_packet.rotation[1] = current.yaw
	sink.deliver(move_packet)
	sink.expect_teleport_ack(current.position)

	tx.wr.broadcast_world_except(rid, p.move_actor_packet())
}

// move_actor_packet is this player's position as other clients see it.
pub fn (p &Player) move_actor_packet() &proto.MoveActorAbsolutePacket {
	current := p.movement()
	mut sink := p.sink
	return &proto.MoveActorAbsolutePacket{
		move_data: proto.MoveActorAbsoluteData{
			actor_runtime_id: proto.actor_runtime_id(sink.runtime_id())
			header:           i8(proto.move_actor_flag_on_ground)
			position_x:       current.position.x
			position_y:       current.position.y
			position_z:       current.position.z
			rotation_x:       proto.rotation_byte(current.pitch)
			rotation_y:       proto.rotation_byte(current.yaw)
			rotation_y_head:  proto.rotation_byte(current.head_yaw)
		}
	}
}

// send_message shows message in the player's chat.
pub fn (mut p Player) send_message(message string) {
	mut sink := p.sink
	sink.deliver(&proto.TextPacket{
		message_type: proto.TextRaw{
			message: message
		}
	})
}

// send_translation shows a client side localised message with parameters
// filling the placeholders in the entry named by key.
pub fn (mut p Player) send_translation(key string, parameters []string) {
	mut sink := p.sink
	sink.deliver(&proto.TextPacket{
		localize:     true
		message_type: proto.TextTranslate{
			message:        key
			parameter_list: parameters
		}
	})
}

// send_slot_update keeps the client's view of one inventory slot in sync
// after the server changed what is in it.
pub fn (mut p Player) send_slot_update(slot int, wrapped types.ItemStackWrapper) {
	mut sink := p.sink
	sink.deliver(&proto.InventorySlotPacket{
		container_id:        u32(inventory_window_id)
		slot:                u32(slot)
		container_name_data: proto.FullContainerName{
			container: .inventory_container
		}
		item:                proto.item_descriptor_v2_tracked(wrapped.item_stack, wrapped.stack_id)
	})
}

// clear_inventory empties the player's inventory and shows the empty result
// to their client. Nobody else can see another player's inventory, so this
// one only speaks through the sink; it takes the transaction because it
// writes state the world actor owns.
pub fn (mut p Player) clear_inventory(mut tx worldrt.WorldTx) {
	p.inv.clear()
	mut items := []proto.NetworkItemStackDescriptorV2{}
	for _ in 0 .. inventory_slot_count {
		items << proto.item_descriptor_v2(types.ItemStack{})
	}
	mut sink := p.sink
	sink.deliver(&proto.InventoryContentPacket{
		inventory_id:        u32(inventory_window_id)
		slots:               items
		container_name_data: proto.FullContainerName{
			container: .inventory_container
		}
		storage_item:        proto.item_descriptor_v2(types.ItemStack{})
	})
}

// give_item puts count of the item named id into the player's inventory and
// shows the new slot to their client. It reports false when id names nothing
// the server knows.
//
// Which slot it lands in is deliberately simplified: the server doesn't keep
// a full slot -> stack map in sync with client driven inventory transactions
// (those are tracked by client assigned network ids), so a
// "first empty slot" search would risk silently colliding with content the
// client already has and thinks the server doesn't know about. Round robining
// across the hotbar via a dedicated counter avoids touching that unrelated
// bookkeeping; it can still overwrite a hotbar slot's visible content.
pub fn (mut p Player) give_item(mut tx worldrt.WorldTx, id string, count int) bool {
	numeric_id := tx.wr.services.game_data().item_id(id)
	if numeric_id == 0 && id != 'minecraft:air' {
		return false
	}
	mut block_runtime_id := 0
	if it := item.get(id) {
		block_runtime_id = it.block_runtime_id()
	}
	slot := p.give_next_slot % hotbar_size
	p.give_next_slot++
	stack := types.ItemStack{
		id:               numeric_id
		meta:             0
		count:            count
		block_runtime_id: block_runtime_id
		raw_extra_data:   []u8{}
	}
	net_id := p.inv.track_stack(stack)
	p.inv.set_slot(slot, net_id)
	p.send_slot_update(slot, types.ItemStackWrapper{
		stack_id:         net_id
		stack_id_variant: 0
		item_stack:       stack
	})
	return true
}

// disconnect kicks the player, showing message as the reason. It takes no
// transaction because closing the connection is the sink's business, not the
// world's.
pub fn (mut p Player) disconnect(message string) {
	mut sink := p.sink
	sink.disconnect(message)
}

// set_gamemode changes the player's game mode and resends what the client is
// allowed to do under it. Cancelling GameModeChangeData leaves the mode alone;
// editing it changes what the player ends up in.
pub fn (mut p Player) set_gamemode(mut tx worldrt.WorldTx, mode Gamemode) {
	mut ctx := event.new_context(GameModeChangeData{
		player: p
		mode:   mode
	})
	p.handler.on_gamemode_change(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	p.set_game_mode(ctx.val.mode)
	mut sink := p.sink
	sink.deliver(&proto.SetPlayerGameTypePacket{
		player_game_type: proto.game_type(gamemode_to_wire(p.game_mode()))
	})
	p.refresh_abilities()
}

// kill takes the player straight to the death path with no attacker, as
// /kill does.
pub fn (mut p Player) kill(mut tx worldrt.WorldTx) {
	if p.is_dead() {
		return
	}
	p.set_health(0)
	mut sink := p.sink
	sink.deliver(p.health_update())
	p.die(mut tx.wr, '%death.attack.generic', [p.identity.display_name])
}

// die is the one death path: combat, /kill and fatal effect damage all end
// here. message_key/parameters are the death broadcast. Cancelling DeathData
// suppresses the death entirely, so a handler that cancels leaves a player
// standing at whatever health the caller already set.
//
// It takes the runtime rather than a transaction because the damage paths
// that reach it are threading the runtime already.
pub fn (mut p Player) die(mut wr worldrt.WorldRuntime, message_key string, parameters []string) {
	mut ctx := event.new_context(DeathData{
		player:      p
		message_key: message_key
		params:      parameters
	})
	p.handler.on_player_death(mut ctx)
	if ctx.is_cancelled() {
		return
	}
	p.set_dead(true)
	mut sink := p.sink
	rid := sink.runtime_id()
	wr.broadcast_world_except(rid, &proto.ActorEventPacket{
		target_runtime_id: proto.actor_runtime_id(rid)
		event_id:          proto.ActorEvent.death
		data:              0
	})
	p.set_last_death(p.position())
	wr.broadcast_world(&proto.TextPacket{
		localize:     true
		message_type: proto.TextTranslate{
			message:        ctx.val.message_key
			parameter_list: parameters
		}
	})
}
