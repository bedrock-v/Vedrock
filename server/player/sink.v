module player

import bedrock_v.protocol.types

// Sink is whatever is driving a player: the one client that is *this* player,
// as opposed to the viewers who merely see them.
//
// Like Viewer it speaks in events rather than packets, so nothing in this
// package has to know the Bedrock wire format in order to tell a client
// something. A player holds one rather than a session and nothing here depends
// on how a client is connected or on there being one at all.
//
// It stays separate from Viewer because these reach the client without going
// through the world: a chat line or a slot correction is owed to one player and
// needs no transaction to prove who can see it.
pub interface Sink {
	// runtime_id is the id this player is known by on the wire.
	runtime_id() u64
	// is_spawned reports whether the client behind this player has finished
	// spawning into a world. Packets that describe the player to everyone
	// else are held back until it has because nobody can see a player who
	// is not in the world yet.
	is_spawned() bool
mut:
	// show_message and show_translation put a line in the client's chat. They
	// are named apart from Player.send_message because a session already has
	// send_message of its own, owed to a command rather than to a player.
	show_message(message string)
	show_translation(key string, parameters []string)
	// send_slot_update and send_armor_slot_update correct the client's view of
	// one slot after the server changed what is in it.
	send_slot_update(slot int, wrapped types.ItemStackWrapper)
	send_armor_slot_update(index int, wrapped types.ItemStackWrapper)
	// send_inventory_cleared shows an empty carried inventory. The worn pieces
	// are separate and are cleared slot by slot.
	send_inventory_cleared()
	// send_game_mode tells the client what it is now allowed to do.
	send_game_mode(mode Gamemode)
	// send_health, send_experience and send_abilities resend one part of the
	// player's own state. They take nothing because the sink knows which
	// player it drives.
	send_health()
	send_experience()
	send_abilities()
	// expect_teleport_ack records a position the server sent unilaterally.
	// Reported movement is discarded until the client confirms it.
	expect_teleport_ack(pos types.Vector3)
	// disconnect closes whatever is driving this player, showing message as
	// the reason where there is somewhere to show it.
	disconnect(message string)
}

// NopSink is a player nobody is connected to. Its events go nowhere which is
// the right behaviour for a player whose session has already gone.
pub struct NopSink {}

pub fn (s &NopSink) runtime_id() u64 {
	return 0
}

pub fn (s &NopSink) is_spawned() bool {
	return false
}

pub fn (mut s NopSink) show_message(message string) {}

pub fn (mut s NopSink) show_translation(key string, parameters []string) {}

pub fn (mut s NopSink) send_slot_update(slot int, wrapped types.ItemStackWrapper) {}

pub fn (mut s NopSink) send_armor_slot_update(index int, wrapped types.ItemStackWrapper) {}

pub fn (mut s NopSink) send_inventory_cleared() {}

pub fn (mut s NopSink) send_game_mode(mode Gamemode) {}

pub fn (mut s NopSink) send_health() {}

pub fn (mut s NopSink) send_experience() {}

pub fn (mut s NopSink) send_abilities() {}

pub fn (mut s NopSink) expect_teleport_ack(pos types.Vector3) {}

pub fn (mut s NopSink) disconnect(message string) {}
