module session

import bedrock_v.protocol
import bedrock_v.protocol.current as proto
import server.internal.logger
import server.internal.network
import sync

// Conn owns a session's connection: the transport, the outbound queue and the
// writer thread that drains it. It holds no gameplay state and never reads
// any, so everything here is safe to run on the writer thread while the world
// actor mutates the player it belongs to.
//
// Policy that needs to know about the player - what to log on overflow, which
// world runtime to report it to, whether a disconnect is graceful - stays on
// NetworkSession, which owns one of these.
@[heap]
struct Conn {
mut:
	transport          network.Transport = FakeTransport{}
	state              State             = .handshake
	encryption_enabled bool
	// The queue carries ticket ids, not packets. A V channel keeps whatever was
	// written into a slot until that slot is written again.
	// only until the writer takes it.
	outbound       chan u64 = chan u64{cap: outbound_queue_capacity}
	pending        map[u64]OutboundMessage
	pending_mutex  &sync.Mutex = sync.new_mutex()
	next_ticket    u64
	done           chan bool = chan bool{cap: 1}
	// abort wakes an idle writer with nothing queued, so close_once can always
	// make it exit, not just when it's mid send.
	abort chan bool = chan bool{cap: 1}
	// writer_exited fires once the writer loop actually returns. Tests use this
	// to know the writer thread is gone, since done only proves close_once ran,
	// not that the writer itself exited.
	writer_exited chan bool   = chan bool{cap: 1}
	close_mutex   &sync.Mutex = sync.new_mutex()
	close_started bool
	// closing is set the moment a graceful disconnect is accepted. Different
	// from close_started: closing means no new packets are accepted but the
	// disconnect message still has to drain; close_started means the transport
	// is actually closed.
	closing bool
	// bootstrap is true while the login sequence still owns transport writes
	// directly. activate clears it once and only before closing begins; test
	// connections default to the active state.
	bootstrap      bool
	writer_mutex   &sync.Mutex = sync.new_mutex()
	writer_started bool
}

// activate transfers transport writes from the bootstrap sequence to the
// writer thread. Returns false if the connection is already closing. Repeated
// calls, including calls for test connections that never entered bootstrap,
// are harmless.
fn (mut c Conn) activate(log &logger.Logger) bool {
	c.close_mutex.lock()
	if c.close_started {
		c.close_mutex.unlock()
		return false
	}
	if !c.bootstrap {
		c.close_mutex.unlock()
		return true
	}
	c.bootstrap = false
	c.close_mutex.unlock()
	c.ensure_writer(log)
	return true
}

// ensure_writer starts the writer the first time it is needed. The lock stops
// concurrent callers from starting duplicates, including for connections built
// directly in tests.
fn (mut c Conn) ensure_writer(log &logger.Logger) {
	c.writer_mutex.lock()
	if c.writer_started {
		c.writer_mutex.unlock()
		return
	}
	c.writer_started = true
	c.writer_mutex.unlock()
	spawn c.run_writer(log)
}

// enqueue adds an outbound message without blocking. Calling it before
// activate is an architecture error and returns one.
//
// The activation check, closing check, disconnect state change and enqueue are
// performed under one lock so nothing can be queued after a disconnect.
fn (mut c Conn) enqueue(msg OutboundMessage, is_disconnect bool, log &logger.Logger) !EnqueueResult {
	c.close_mutex.lock()
	if c.bootstrap {
		c.close_mutex.unlock()
		return error('outbound message enqueued before activate_outbound()')
	}
	if c.closing || c.close_started {
		c.close_mutex.unlock()
		return .closing
	}
	if is_disconnect {
		c.closing = true
	}
	c.ensure_writer(log)
	ticket := c.hold(msg)
	mut result := EnqueueResult.queue_full
	select {
		c.outbound <- ticket {
			result = .enqueued
		}
		else {
			result = .queue_full
		}
	}
	if result != .enqueued {
		c.take(ticket)
	}
	c.close_mutex.unlock()
	return result
}

// hold parks msg under a fresh ticket for the writer to collect.
fn (mut c Conn) hold(msg OutboundMessage) u64 {
	c.pending_mutex.lock()
	c.next_ticket++
	ticket := c.next_ticket
	c.pending[ticket] = msg
	c.pending_mutex.unlock()
	return ticket
}

// take removes and returns a parked message. none when the ticket was already
// collected or dropped because it never made it onto the queue.
fn (mut c Conn) take(ticket u64) ?OutboundMessage {
	c.pending_mutex.lock()
	defer {
		c.pending_mutex.unlock()
	}
	msg := c.pending[ticket] or { return none }
	c.pending.delete(ticket)
	return msg
}

// discard drops every parked message, so a closed connection stops holding
// packets its writer will never collect.
fn (mut c Conn) discard() {
	c.pending_mutex.lock()
	c.pending = map[u64]OutboundMessage{}
	c.pending_mutex.unlock()
}

// bootstrapping reports whether the login sequence still owns transport
// writes.
fn (mut c Conn) bootstrapping() bool {
	c.close_mutex.lock()
	defer {
		c.close_mutex.unlock()
	}
	return c.bootstrap
}

// send_direct writes p straight to the transport if the connection is still
// bootstrapping and reports whether it did. The bootstrap check and the write
// share one lock so activate can't hand the transport to the writer while a
// direct write is still in progress.
fn (mut c Conn) send_direct(p protocol.Packet) !bool {
	c.close_mutex.lock()
	if !c.bootstrap {
		c.close_mutex.unlock()
		return false
	}
	c.transport.send(p) or {
		c.close_mutex.unlock()
		return err
	}
	c.close_mutex.unlock()
	return true
}

// send_batch_direct is send_direct for a batch. See its comment for why the
// check and the write share one lock.
fn (mut c Conn) send_batch_direct(packets []protocol.Packet) !bool {
	c.close_mutex.lock()
	if !c.bootstrap {
		c.close_mutex.unlock()
		return false
	}
	c.transport.send_batch(packets) or {
		c.close_mutex.unlock()
		return err
	}
	c.close_mutex.unlock()
	return true
}

// close_once closes the transport and signals completion exactly once. It also
// wakes an idle writer so the thread can't remain blocked on an empty queue
// after shutdown.
fn (mut c Conn) close_once() {
	c.close_mutex.lock()
	if c.close_started {
		c.close_mutex.unlock()
		return
	}
	c.close_started = true
	c.close_mutex.unlock()
	c.transport.close()
	select {
		c.abort <- true {}
		else {}
	}
	// Anything still parked is never going to be written now.
	c.discard()
	c.done <- true
}

// run_writer sends queued messages in order and handles socket writes away
// from the calling thread. An abort may interrupt the queue immediately,
// including while the writer is idle.
fn (mut c Conn) run_writer(log &logger.Logger) {
	logger.name_thread('Outbound/${c.transport.remote_addr()}')
	defer {
		logger.unname_thread()
	}
	defer {
		select {
			c.writer_exited <- true {}
			else {}
		}
	}
	for {
		select {
			ticket := <-c.outbound {
				msg := c.take(ticket) or { continue }
				match msg {
					OutboundPacket {
						c.transport.send(msg.packet) or {
							log.debug('outbound write failed: ${err}')
							c.state = .closed
							c.close_once()
							return
						}
					}
					OutboundBatch {
						c.transport.send_batch(msg.packets) or {
							log.debug('outbound batch write failed: ${err}')
							c.state = .closed
							c.close_once()
							return
						}
					}
					OutboundDisconnect {
						c.transport.send(&proto.DisconnectPacket{
							reason:  proto.connection_fail_disconnect_packet
							message: proto.DisconnectMessage{
								kick_message:     msg.message
								filtered_message: ''
							}
						}) or {}
						c.state = .closed
						c.close_once()
						return
					}
				}
			}
			_ := <-c.abort {
				return
			}
		}
	}
}
