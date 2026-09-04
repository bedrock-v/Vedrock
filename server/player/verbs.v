module player

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

// teleport moves the player to pos and shows the arrival to everyone who can
// see them, their own client included. What each of them is sent differs but
// that is the viewer's decision, not this verb's.
pub fn (mut p Player) teleport(mut tx worldrt.WorldTx, pos types.Vector3) {
	p.reset_position(pos)
	for mut v in p.viewers(mut tx) {
		v.view_teleport(p, pos)
	}
}

// send_message shows message in the player's chat.
pub fn (mut p Player) send_message(message string) {
	mut sink := p.sink
	sink.show_message(message)
}

// send_translation shows a client side localised message with parameters
// filling the placeholders in the entry named by key.
pub fn (mut p Player) send_translation(key string, parameters []string) {
	mut sink := p.sink
	sink.show_translation(key, parameters)
}

// send_slot_update keeps the client's view of one inventory slot in sync
// after the server changed what is in it.
pub fn (mut p Player) send_slot_update(slot int, wrapped types.ItemStackWrapper) {
	mut sink := p.sink
	sink.send_slot_update(slot, wrapped)
}

// clear_inventory empties the player's inventory and shows the empty result
// to their client. Nobody else can see another player's inventory, so this
// one only speaks through the sink; it takes the transaction because it
// writes state the world actor owns.
pub fn (mut p Player) clear_inventory(mut tx worldrt.WorldTx) {
	p.inv.clear()
	mut sink := p.sink
	sink.send_inventory_cleared()
	// The worn pieces live in the same stack map, so clearing it took them
	// too - the client has to be told about its own armor window separately.
	for index in 0 .. armor_slot_count {
		p.send_armor_slot_update(index, types.ItemStackWrapper{})
	}
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

// heal raises the player's health by amount, up to the twenty point maximum,
// and tells their client the new value. It takes no transaction because
// nobody else sees another player's health bar.
pub fn (mut p Player) heal(amount f32) {
	if p.is_dead() || amount <= 0 {
		return
	}
	old := p.health()
	mut new_health := old + amount
	if new_health > 20 {
		new_health = 20
	}
	p.set_health(new_health)
	if new_health != old {
		p.send_health()
	}
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
	sink.send_game_mode(p.game_mode())
	p.refresh_abilities()
}

// kill takes the player straight to the death path with no attacker, as
// /kill does.
pub fn (mut p Player) kill(mut tx worldrt.WorldTx) {
	if p.is_dead() {
		return
	}
	p.set_health(0)
	p.send_health()
	p.die(mut tx, '%death.attack.generic', [p.identity.display_name])
}

// die is the one death path: combat, /kill and fatal effect damage all end
// here. message_key/parameters are the death broadcast. Cancelling DeathData
// suppresses the death entirely, so a handler that cancels leaves a player
// standing at whatever health the caller already set.
pub fn (mut p Player) die(mut tx worldrt.WorldTx, message_key string, parameters []string) {
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
	p.set_last_death(p.position())
	p.drop_experience(mut tx)
	for mut v in p.viewers(mut tx) {
		v.view_death(p, ctx.val.message_key, parameters)
	}
}

// send_health, refresh_abilities and the other resends below reach only the
// player's own client, so they go through the sink rather than the world.

// send_health pushes the current health to the player's own client. A client
// that has not spawned yet has no health bar to correct.
pub fn (mut p Player) send_health() {
	mut sink := p.sink
	if !sink.is_spawned() {
		return
	}
	sink.send_health()
}

// refresh_abilities resends what the client is allowed to do after something
// that changes it such as a game mode change or an op grant.
pub fn (mut p Player) refresh_abilities() {
	mut sink := p.sink
	sink.send_abilities()
}
