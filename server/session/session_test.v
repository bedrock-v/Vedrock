module session

import math
import sync
import bedrock_v.protocol
import bedrock_v.protocol.packets
import server.network
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

fn (mut t FakeTransport) buffered_amount() u64 {
	return 0
}

fn (mut t FakeTransport) close() {}

// move_to is the input a client sends with its feet at x, y, z.
// It names where its eyes are.
fn move_to(x f32, y f32, z f32) protocol.Packet {
	return &packets.PlayerAuthInputPacket{
		player_position: [x, y + network.eye_height, z]!
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
	mut s := new_session(mut t, h, 2)
	s.run()

	r := world.ref[Player](h)
	pos := world.call_ref[Player, [3]f32](r, 'test.pos', fn (mut tx world.Tx, e &Player) ![3]f32 {
		return e.position
	})!

	assert pos[0] == 1 && pos[2] == 3
	assert math.abs(pos[1] - 2) < 0.0001

	actor := world.call[u64](mut wr, 'test.actor', fn (mut tx world.Tx) !u64 {
		return sync.thread_id()
	})!
	assert t.read_from == sync.thread_id()
	assert actor != t.read_from
}
