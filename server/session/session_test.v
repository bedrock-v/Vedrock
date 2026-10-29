module session

import math
import sync
import time
import bedrock_v.protocol
import bedrock_v.protocol.packets
import bedrock_v.protocol.types
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

fn test_packets_are_handled_in_order() {
	mut wr := world.start('overworld')
	defer {
		wr.close()
	}
	h := spawn_player(mut wr, 2)

	mut t := &FakeTransport{
		incoming: [move_to(1, 0, 0), move_to(2, 0, 0), move_to(3, 0, 0)]
	}
	mut s := new_session(mut t, h, 2)
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
	mut s := new_session(mut t, h, 2)
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
	mut s := new_session(mut t, h, 2)
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
	mut s := new_session(mut t, h, 2)
	s.run()

	where := world.call_ref[Player, string](r, 'test.where', fn (mut tx world.Tx, e &Player) !string {
		return '${tx.world_name()}:${e.position[0]}'
	})!
	assert where == 'b:7.0'
}

// LiveTransport is a client that stays connected until it is closed: reads wait
// for packets the test sends and writes are kept for the test to look at while
// the session runs.
struct LiveTransport {
mut:
	mu       &sync.Mutex          = sync.new_mutex()
	incoming chan protocol.Packet = chan protocol.Packet{cap: 16}
	written  []protocol.Packet
	buffered u64
	closed   bool
}

fn (mut t LiveTransport) read() !protocol.Packet {
	p := <-t.incoming or { return error('closed') }
	return p
}

fn (mut t LiveTransport) write(p protocol.Packet) ! {
	t.mu.lock()
	t.written << p
	t.mu.unlock()
}

fn (mut t LiveTransport) buffered_amount() u64 {
	t.mu.lock()
	defer {
		t.mu.unlock()
	}
	return t.buffered
}

fn (mut t LiveTransport) close() {
	t.mu.lock()
	if !t.closed {
		t.closed = true
		t.incoming.close()
	}
	t.mu.unlock()
}

fn (mut t LiveTransport) is_closed() bool {
	t.mu.lock()
	defer {
		t.mu.unlock()
	}
	return t.closed
}

// level_chunks are the chunks written so far in order.
fn (mut t LiveTransport) level_chunks() []types.ChunkPos {
	t.mu.lock()
	defer {
		t.mu.unlock()
	}
	mut out := []types.ChunkPos{}
	for p in t.written {
		if p is packets.LevelChunkPacket {
			out << p.chunk_position
		}
	}
	return out
}

fn (mut t LiveTransport) count[T]() int {
	t.mu.lock()
	defer {
		t.mu.unlock()
	}
	mut n := 0
	for p in t.written {
		if p is T {
			n++
		}
	}
	return n
}

// wait_for waits up to two seconds for a condition about what was written.
fn wait_for(mut t LiveTransport, done fn (mut t LiveTransport) bool) bool {
	for _ in 0 .. 200 {
		if done(mut t) {
			return true
		}
		time.sleep(10 * time.millisecond)
	}
	return false
}

fn test_chunks_around_a_player_arrive_a_few_each_tick_nearest_first() {
	mut wr := world.start('overworld')
	defer {
		wr.close()
	}
	h := spawn_player(mut wr, 6)
	mut t := &LiveTransport{}
	mut s := new_session(mut t, h, 2)
	runner := spawn fn [mut s] () {
		s.run()
	}()

	all_sent := wait_for(mut t, fn (mut t LiveTransport) bool {
		return t.level_chunks().len >= 13
	})
	t.close()
	runner.wait()
	assert all_sent, 'only ${t.level_chunks().len} of 13 chunks arrived'
	chunks := t.level_chunks()
	assert chunks.len == 13, 'a chunk was sent twice'
	assert chunks[0] == types.ChunkPos{0, 0}, 'the chunk the player is in was not first'
	assert t.count[packets.NetworkChunkPublisherUpdatePacket]() == 1
}
