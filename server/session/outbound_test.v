module session

import time
import protocol
import server.internal.encryption
import server.internal.gamedata
import server.internal.auth
import server.internal.logger
import server.player
import server.world
import server.world.db

@[heap]
struct BlockingFakeTransport {
mut:
	sent        []protocol.Packet
	sent_notify chan bool = chan bool{cap: 256}
	block_next  bool
	started     chan bool = chan bool{cap: 1}
	release     chan bool = chan bool{cap: 1}
	closed      chan bool = chan bool{cap: 1}
}

fn (mut t BlockingFakeTransport) block_next_send() {
	t.block_next = true
}

fn (mut t BlockingFakeTransport) wait_started() {
	_ := <-t.started
}

fn (mut t BlockingFakeTransport) release_send() {
	select {
		t.release <- true {}
		else {}
	}
}

fn (mut t BlockingFakeTransport) send(p protocol.Packet) ! {
	if t.block_next {
		t.block_next = false
		t.started <- true
		select {
			_ := <-t.release {}
			_ := <-t.closed {
				return error('transport closed while send was blocked')
			}
		}
	}
	t.sent << p
	select {
		t.sent_notify <- true {}
		else {}
	}
}

fn (mut t BlockingFakeTransport) send_batch(packets []protocol.Packet) ! {
	t.sent << packets
	select {
		t.sent_notify <- true {}
		else {}
	}
}

fn (mut t BlockingFakeTransport) read() ![]protocol.Packet {
	return []protocol.Packet{}
}

fn (t &BlockingFakeTransport) remote_addr() string {
	return 'fake-blocking:0'
}

fn (mut t BlockingFakeTransport) close() {
	select {
		t.closed <- true {}
		else {}
	}
}

fn (mut t BlockingFakeTransport) mark_logged_in() {}

fn (mut t BlockingFakeTransport) enable_compression(threshold int) {}

fn (mut t BlockingFakeTransport) enable_encryption(mut ctx encryption.Context) {}

fn outbound_test_session(mut transport BlockingFakeTransport) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	return &NetworkSession{
		player:     pl
		runtime_id: 1
		transport:  transport
		hub:        new_hub(gamedata.GameData{})
		log:        logger.new(.info)
	}
}

fn blocking_sent_text(transport &BlockingFakeTransport, want int, timeout_ms int) bool {
	mut remaining := timeout_ms * time.millisecond
	for transport.sent.len < want {
		waited_from := time.now()
		select {
			_ := <-transport.sent_notify {}
			remaining {
				return transport.sent.len >= want
			}
		}
		remaining -= time.now() - waited_from
		if remaining <= 0 {
			return transport.sent.len >= want
		}
	}
	return true
}

fn test_outbound_preserves_order_before_disconnect() {
	mut transport := &BlockingFakeTransport{}
	mut s := outbound_test_session(mut transport)

	s.deliver(&protocol.TextPacket{
		message: 'A'
	})
	s.deliver(&protocol.TextPacket{
		message: 'B'
	})
	s.disconnect('bye')

	assert blocking_sent_text(transport, 3, 2000)
	assert transport.sent.len == 3
	if a := transport.sent[0] {
		if a is protocol.TextPacket {
			assert a.message == 'A'
		} else {
			assert false
		}
	}
	if b := transport.sent[1] {
		if b is protocol.TextPacket {
			assert b.message == 'B'
		} else {
			assert false
		}
	}
	if c := transport.sent[2] {
		assert c is protocol.DisconnectPacket
	}
	_ := <-s.outbound_done
	assert s.state == .closed
}

fn test_outbound_overflow_aborts_session() {
	mut transport := &BlockingFakeTransport{}
	mut s := outbound_test_session(mut transport)

	transport.block_next_send()
	s.deliver(&protocol.TextPacket{
		message: 'first'
	})
	transport.wait_started()

	for i in 0 .. outbound_queue_capacity {
		s.deliver(&protocol.TextPacket{
			message: 'fill${i}'
		})
	}
	assert s.state != .closed

	s.deliver(&protocol.TextPacket{
		message: 'overflow'
	})
	assert s.state == .closed

	transport.release_send()
	_ := <-s.outbound_done
}

fn test_abort_outbound_releases_blocked_writer_once() {
	mut transport := &BlockingFakeTransport{}
	mut s := outbound_test_session(mut transport)

	transport.block_next_send()
	s.deliver(&protocol.TextPacket{
		message: 'will not complete'
	})
	transport.wait_started()

	s.abort_outbound()

	select {
		_ := <-s.outbound_done {}
		1000 * time.millisecond {
			assert false // abort_outbound's close() should have unblocked the writer's pending send
		}
	}
	assert s.state == .closed
}

fn test_world_broadcast_does_not_wait_for_slow_session() {
	mut hub := new_hub(gamedata.GameData{})
	target := db.new_world('world', none, 'void', world.overworld)
	hub.add_world(target)
	mut wr := hub.world_runtime('world') or { panic('expected world runtime') }
	defer {
		hub.close_worlds()
	}

	mut transport := &BlockingFakeTransport{}
	mut s := outbound_test_session(mut transport)
	s.world = wr.world
	s.world_runtime = wr
	hub.add(s)
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }

	transport.block_next_send()

	done := chan bool{cap: 1}
	spawn fn [mut wr, done] () {
		world_call[bool](mut wr, fn (mut tx WorldTx) bool {
			tx.wr.broadcast_world(&protocol.TextPacket{
				message: 'hello'
			})
			return true
		}) or {}
		done <- true
	}()

	select {
		_ := <-done {}
		500 * time.millisecond {
			assert false // the world actor's broadcast blocked on a slow session transport.
		}
	}

	transport.wait_started()
	transport.release_send()
	assert blocking_sent_text(transport, 1, 1000)
}

fn bootstrap_test_session(mut transport FakeTransport) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	return &NetworkSession{
		player:             pl
		runtime_id:         1
		transport:          transport
		hub:                new_hub(gamedata.GameData{})
		log:                logger.new(.info)
		outbound_bootstrap: true
	}
}

fn bootstrap_test_session_blocking(mut transport BlockingFakeTransport) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	return &NetworkSession{
		player:             pl
		runtime_id:         1
		transport:          transport
		hub:                new_hub(gamedata.GameData{})
		log:                logger.new(.info)
		outbound_bootstrap: true
	}
}

fn test_outbound_enqueue_fails_before_activation_then_succeeds_after() {
	mut transport := &FakeTransport{}
	mut s := bootstrap_test_session(mut transport)

	if _ := s.send_packet(&protocol.TextPacket{
		message: 'too early'
	})
	{
		assert false
	}
	if _ := s.send_batch([protocol.Packet(&protocol.TextPacket{
		message: 'too early'
	})])
	{
		assert false
	}
	assert transport.sent.len == 0
	assert s.state != .closed

	s.activate_outbound()

	s.send_packet(&protocol.TextPacket{
		message: 'A'
	}) or { assert false }
	s.send_batch([protocol.Packet(&protocol.TextPacket{
		message: 'B'
	})]) or { assert false }
	s.deliver(&protocol.TextPacket{
		message: 'C'
	})
	assert wait_for_sent_len(transport, 3, 2000)
}

fn wait_for_sent_len(transport &FakeTransport, want int, timeout_ms int) bool {
	mut remaining := timeout_ms * time.millisecond
	for transport.sent.len < want {
		waited_from := time.now()
		select {
			_ := <-transport.sent_notify {}
			remaining {
				return transport.sent.len >= want
			}
		}
		remaining -= time.now() - waited_from
		if remaining <= 0 {
			return transport.sent.len >= want
		}
	}
	return true
}

fn test_send_batch_stays_adjacent_against_concurrent_deliver() {
	mut transport := &BlockingFakeTransport{}
	mut s := outbound_test_session(mut transport)

	done := chan bool{cap: 2}
	spawn fn [mut s, done] () {
		s.send_batch([
			protocol.Packet(&protocol.TextPacket{
				message: 'A'
			}),
			protocol.Packet(&protocol.TextPacket{
				message: 'B'
			}),
			protocol.Packet(&protocol.TextPacket{
				message: 'C'
			}),
		]) or {}
		done <- true
	}()
	spawn fn [mut s, done] () {
		s.deliver(&protocol.TextPacket{
			message: 'X'
		})
		done <- true
	}()
	_ := <-done
	_ := <-done

	assert blocking_sent_text(transport, 4, 2000)
	assert transport.sent.len == 4

	mut abc_start := -1
	for i, p in transport.sent {
		if p is protocol.TextPacket {
			if p.message == 'A' {
				abc_start = i
			}
		}
	}
	assert abc_start >= 0
	assert abc_start + 2 < transport.sent.len
	if b := transport.sent[abc_start + 1] {
		if b is protocol.TextPacket {
			assert b.message == 'B'
		} else {
			assert false
		}
	}
	if c := transport.sent[abc_start + 2] {
		if c is protocol.TextPacket {
			assert c.message == 'C'
		} else {
			assert false
		}
	}
}

fn test_activation_waits_for_bootstrap_direct_send() {
	mut transport := &BlockingFakeTransport{}
	mut s := bootstrap_test_session_blocking(mut transport)

	transport.block_next_send()
	send_done := chan bool{cap: 1}
	spawn fn [mut s, send_done] () {
		s.send_maybe_queued(&protocol.TextPacket{
			message: 'bootstrap direct'
		}) or {}
		send_done <- true
	}()
	transport.wait_started()

	activated := chan bool{cap: 1}
	spawn fn [mut s, activated] () {
		result := s.activate_outbound()
		activated <- result
	}()

	select {
		_ := <-activated {
			assert false // activate_outbound() completed while the bootstrap direct send was still in flight
		}
		300 * time.millisecond {}
	}

	transport.release_send()
	_ := <-send_done

	select {
		result := <-activated {
			assert result
		}
		1000 * time.millisecond {
			assert false // activate_outbound() should complete promptly once the direct send finishes
		}
	}
}

fn test_disconnect_rejects_later_packet_enqueue() {
	mut transport := &BlockingFakeTransport{}
	mut s := outbound_test_session(mut transport)

	s.disconnect('bye')
	if _ := s.send_packet(&protocol.TextPacket{
		message: 'too late'
	})
	{
		assert false // send_packet must refuse once disconnect's been accepted
	}

	assert blocking_sent_text(transport, 1, 2000)
	assert transport.sent.len == 1
	if p := transport.sent[0] {
		assert p is protocol.DisconnectPacket
	}
	_ := <-s.outbound_done
}

fn test_abort_stops_idle_outbound_writer() {
	mut transport := &BlockingFakeTransport{}
	mut s := outbound_test_session(mut transport)

	s.deliver(&protocol.TextPacket{
		message: 'warmup'
	})
	assert blocking_sent_text(transport, 1, 2000)

	s.abort_outbound()
	_ := <-s.outbound_done
	select {
		_ := <-s.writer_exited {}
		1000 * time.millisecond {
			assert false // the writer never exited - the idle-writer leak is still present
		}
	}

	leaked_msg := OutboundMessage(OutboundPacket{
		packet: &protocol.TextPacket{
			message: 'leaked'
		}
	})
	select {
		s.outbound <- leaked_msg {}
		else {}
	}
	select {
		_ := <-transport.sent_notify {
			assert false // a leaked writer thread picked up the message injected after abort
		}
		300 * time.millisecond {}
	}
	assert transport.sent.len == 1
}

fn test_activation_fails_when_session_is_closing() {
	mut transport := &FakeTransport{}
	mut s := bootstrap_test_session(mut transport)

	s.abort_outbound()
	assert !s.activate_outbound()
}

fn overflow_world_test_session_blocking(mut hub Hub, mut wr WorldRuntime, mut transport BlockingFakeTransport) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	mut s := &NetworkSession{
		player:        pl
		runtime_id:    hub.allocate_runtime_id()
		transport:     transport
		hub:           hub
		world:         wr.world
		world_runtime: wr
		generator:     world.VoidGenerator{}
		log:           logger.new(.info)
	}
	hub.add(s)
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn overflow_world_test_session(mut hub Hub, mut wr WorldRuntime, mut transport FakeTransport) &NetworkSession {
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	mut s := &NetworkSession{
		player:        pl
		runtime_id:    hub.allocate_runtime_id()
		transport:     transport
		hub:           hub
		world:         wr.world
		world_runtime: wr
		generator:     world.VoidGenerator{}
		log:           logger.new(.info)
	}
	hub.add(s)
	world_call[bool](mut wr, fn [s] (mut tx WorldTx) bool {
		tx.register_player(s)
		return true
	}) or { panic('registration rejected - world unexpectedly stopped') }
	return s
}

fn test_overflowing_session_doesnt_block_broadcast_to_others() {
	mut hub := new_hub(gamedata.GameData{})
	world_a := db.new_world('overflow-a', none, 'void', world.overworld)
	hub.add_world(world_a)
	world_b := db.new_world('overflow-b', none, 'void', world.overworld)
	hub.add_world(world_b)
	mut wr_a := hub.world_runtime('overflow-a') or { panic('expected world runtime a') }
	mut wr_b := hub.world_runtime('overflow-b') or { panic('expected world runtime b') }
	defer {
		hub.close_worlds()
	}

	mut overflowing_transport := &BlockingFakeTransport{}
	mut overflowing_session := overflow_world_test_session_blocking(mut hub, mut wr_a, mut
		overflowing_transport)
	mut healthy_transport := &FakeTransport{}
	overflow_world_test_session(mut hub, mut wr_a, mut healthy_transport)
	mut other_world_transport := &FakeTransport{}
	overflow_world_test_session(mut hub, mut wr_b, mut other_world_transport)

	overflowing_transport.block_next_send()
	overflowing_session.deliver(&protocol.TextPacket{
		message: 'blocks the writer'
	})
	overflowing_transport.wait_started()
	for i in 0 .. outbound_queue_capacity {
		overflowing_session.deliver(&protocol.TextPacket{
			message: 'fill${i}'
		})
	}
	assert overflowing_session.state != .closed

	done := chan bool{cap: 1}
	spawn fn [mut wr_a, done] () {
		world_call[bool](mut wr_a, fn (mut tx WorldTx) bool {
			tx.wr.broadcast_world(&protocol.TextPacket{
				message: 'broadcast'
			})
			return true
		}) or {}
		done <- true
	}()

	select {
		_ := <-done {}
		1000 * time.millisecond {
			assert false // the overflowing session's own abort blocked delivery to the rest of its world
		}
	}

	assert overflowing_session.state == .closed
	assert wait_for_sent_len(healthy_transport, 1, 2000)

	world_call[bool](mut wr_b, fn (mut tx WorldTx) bool {
		tx.wr.broadcast_world(&protocol.TextPacket{
			message: 'other world'
		})
		return true
	}) or { panic('world b broadcast rejected - unaffected by world a overflow') }
	assert wait_for_sent_len(other_world_transport, 1, 2000)
}

fn test_repeated_calls_after_disc_do_not_duplicate_effects() {
	mut transport := &FakeTransport{}
	mut pl := player.new_player()
	pl.identity = auth.Identity{
		display_name: 'Alex'
	}
	mut s := &NetworkSession{
		player:     pl
		runtime_id: 1
		transport:  transport
		hub:        new_hub(gamedata.GameData{})
		log:        logger.new(.info)
	}

	s.disconnect('bye')
	assert wait_for_sent_len(transport, 1, 2000)
	_ := <-s.outbound_done

	s.disconnect('bye again')
	s.deliver(&protocol.TextPacket{
		message: 'late'
	})
	s.abort_outbound()

	select {
		_ := <-s.outbound_done {
			assert false // close_outbound_once fired more than once
		}
		300 * time.millisecond {}
	}

	mut disconnect_count := 0
	for p in transport.sent {
		if p is protocol.DisconnectPacket {
			disconnect_count++
		}
	}
	assert disconnect_count == 1
	assert transport.sent.len == 1
}
