module player

import bedrock_v.protocol
import bedrock_v.protocol.types

// Sink is whatever is driving a player: what the player needs in order to act
// on the client behind it. A player holds one rather than a session, so
// nothing in this package depends on how a client is connected or on there
// being one at all.
pub interface Sink {
	// runtime_id is the id this player is known by on the wire.
	runtime_id() u64
	// is_spawned reports whether the client behind this player has finished
	// spawning into a world. Packets that describe the player to everyone
	// else are held back until it has because nobody can see a player who
	// is not in the world yet.
	is_spawned() bool
mut:
	deliver(p protocol.Packet)
	// expect_teleport_ack records a position the server sent unilaterally.
	// Reported movement is discarded until the client confirms it.
	expect_teleport_ack(pos types.Vector3)
	// disconnect closes whatever is driving this player, showing message as
	// the reason where there is somewhere to show it.
	disconnect(message string)
}

// NopSink is a player nobody is connected to. Its packets go nowhere which
// is the right behaviour for a player whose session has already gone.
pub struct NopSink {}

pub fn (s &NopSink) runtime_id() u64 {
	return 0
}

pub fn (s &NopSink) is_spawned() bool {
	return false
}

pub fn (mut s NopSink) deliver(p protocol.Packet) {}

pub fn (mut s NopSink) expect_teleport_ack(pos types.Vector3) {}

pub fn (mut s NopSink) disconnect(message string) {}
