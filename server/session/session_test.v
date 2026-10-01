module session

import sync
import bedrock_v.protocol
import bedrock_v.protocol.packets
import bedrock_v.protocol.types
import server.world

// FakeTransport hands over a fixed list of packets and keeps what was written
// and a test drives a session without a socket. It also records the thread each
// packet was read on which is how the read loop is told apart from the world.
struct FakeTransport {
mut:
	incoming  []protocol.Packet
	next      int
	written   []protocol.Packet
	read_from u64
}

fn (mut t FakeTransport) read() !protocol.Packet {
	if t.next >= t.incoming.len {
		return error('no more packets')
	}
	t.read_from = sync.thread_id()
	p := t.incoming[t.next]
	t.next++
	return p
}

fn (mut t FakeTransport) write(p protocol.Packet) ! {
	t.written << p
}

fn (mut t FakeTransport) close() {}

fn move_to(x f32, y f32, z f32) protocol.Packet {
	return &packets.MovePlayerPacket{
		player_runtime_id: types.ActorRuntimeID{
			value: 1
		}
		position:          [x, y, z]!
		rotation:          [f32(0), 0]!
	}
}

fn spawn_player(mut wr world.Runtime, id u64) &world.Handle {
	h := world.new_handle(id, &Player{
		id_: id
	})
	world.call[bool](mut wr, 'test.spawn', fn [h] (mut tx world.Tx) !bool {
		tx.add(h)
		return true
	}) or { panic(err) }
	return h
}

fn test_a_packet_is_handled_on_the_world_that_holds_the_player() {
	mut wr := world.start('overworld')
	defer {
		wr.close()
	}
	h := spawn_player(mut wr, 1)

	mut t := &FakeTransport{
		incoming: [move_to(1, 2, 3)]
	}
	mut s := new_session(mut t, h)
	s.run()

	r := world.ref[Player](h)
	pos := server.world.call_ref[Player, [3]f32{}](r, 'test.pos', fn (mut tx world.Tx, e &Player) ![3]f32 {
		return e.position
	})!

	assert pos == [f32(1), 2, 3]!

	actor := world.call[u64](mut wr, 'test.actor', fn (mut tx world.Tx) !u64 {
		return sync.thread_id()
	})!
	assert t.read_from == sync.thread_id()
	assert actor != t.read_from
}

fn test_packets_are_handled_in_order() {
	mut wr := world.start('overworld')
	defer {
		wr.close()
	}
	h := spawn_player(mut wr, 2)

	mut t := &FakeTransport{
		incoming: [move_to(1, 0, 0), move_to(2, 0, 0), move_to(3, 0, 0)]
	}
	mut s := new_session(mut t, h)
	s.run()

	r := world.ref[Player](h)
	state := world.call_ref[Player, string](r, 'test.state', fn (mut tx world.Tx, e &Player) !string {
		return '${e.moves}:${e.position[0]}'
	})!
	assert state == '3:3.0'
}

fn test_an_unhandled_packet_does_not_stop_the_session() {
	mut wr := world.start('overworld')
	defer {
		wr.close()
	}
	h := spawn_player(mut wr, 3)

	mut t := &FakeTransport{
		incoming: [&packets.TextPacket{}, move_to(9, 0, 0)]
	}
	mut s := new_session(mut t, h)
	s.run()

	r := world.ref[Player](h)
	moves := world.call_ref[Player, int](r, 'test.moves', fn (mut tx world.Tx, e &Player) !int {
		return e.moves
	})!
	assert moves == 1
}

fn test_a_packet_for_a_player_in_no_world_fails() {
	mut wr := world.start('overworld')
	defer {
		wr.close()
	}
	h := spawn_player(mut wr, 4)
	world.call[bool](mut wr, 'test.remove', fn (mut tx world.Tx) !bool {
		tx.remove(4) or { return error('not here') }
		return true
	})!

	mut t := &FakeTransport{
		incoming: [move_to(1, 1, 1)]
	}
	mut s := new_session(mut t, h)
	if _ := s.handle_packet(move_to(1, 1, 1)) {
		assert false, 'a packet was handled for a player in no world'
	}
	// The loop itself survives it.
	s.run()
}

fn test_packets_follow_the_player_to_another_world() {
	mut a := world.start('a')
	mut b := world.start('b')
	defer {
		a.close()
		b.close()
	}
	h := spawn_player(mut a, 5)
	r := world.ref[Player](h)
	world.transfer_ref[Player](r, b)!

	mut t := &FakeTransport{
		incoming: [move_to(7, 7, 7)]
	}
	mut s := new_session(mut t, h)
	s.run()

	where := world.call_ref[Player, string](r, 'test.where', fn (mut tx world.Tx, e &Player) !string {
		return '${tx.world_name()}:${e.position[0]}'
	})!
	assert where == 'b:7.0'
}
