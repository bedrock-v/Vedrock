module session

import protocol
import protocol.packets
import vedrock.server.world

// Transport is one client's connection, framed into packets. A session reads
// and writes packets through it and knows nothing about how they travel.
pub interface Transport {
mut:
	read() !protocol.Packet
	write(p protocol.Packet) !
	close()
}

// Player is the entity a session controls. Like any entity, it belongs to a
// world and is reached through that world's transaction.
pub struct Player {
	id_ u64
pub mut:
	position [3]f32
	rotation [2]f32
	// moves counts the movement packets handled so far.
	moves int
}

pub fn (p &Player) id() u64 {
	return p.id_
}

// Session runs one client: it reads that client's packets and handles them on
// the world its player is in.
pub struct Session {
mut:
	transport Transport
	handle    &world.Handle
	player    world.Ref[Player]
}

// new_session builds a session for a player that is already in a world.
pub fn new_session(mut t Transport, h &world.Handle) &Session {
	return &Session{
		transport: t
		handle:    h
		player:    world.ref[Player](h)
	}
}

// run reads and handles packets until the transport runs out of them. Each
// packet is handled before the next is read, which keeps them in the order the
// client sent them.
pub fn (mut s Session) run() {
	for {
		p := s.transport.read() or { return }
		s.handle_packet(p) or { continue }
	}
}

// handle_packet runs a packet inside a transaction on the world holding the
// player and waits for it.
//
// Chat, commands and forms act on players in other worlds, which needs a
// transaction on each of those worlds. They are handled elsewhere.
fn (mut s Session) handle_packet(p protocol.Packet) ! {
	world.call_ref[Player, bool](s.player, 'session.packet', fn [p] (mut tx world.Tx, e &Player) !bool {
		mut pl := unsafe { e }
		dispatch(mut tx, mut pl, p)!
		return true
	})!
}

// dispatch hands a packet to its handler. It runs on the world's thread, inside
// the transaction it is given.
fn dispatch(mut tx world.Tx, mut pl Player, p protocol.Packet) ! {
	if p is packets.MovePlayerPacket {
		pl.position = p.position
		pl.rotation = p.rotation
		pl.moves++
		return
	}
	return error('no handler for ${p.name()} in world "${tx.world_name()}"')
}
