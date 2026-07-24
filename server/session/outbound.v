module session

import protocol

// Maximum number of packets a session may have waiting to be sent.
// A full queue aborts the session instead of blocking the caller or
// allowing the client to fall out of sync.
const outbound_queue_capacity = 256

// OutboundPacket is a single packet queued for delivery.
struct OutboundPacket {
	packet protocol.Packet
}

// OutboundBatch keeps a group of packets consecutive on the wire, so
// packets queued by another thread can't be inserted between them.
struct OutboundBatch {
	packets []protocol.Packet
}

// OutboundDisconnect ends the session after all packets queued before it
// have been sent.
struct OutboundDisconnect {
	message string
}

// OutboundMessage represents the packets and control messages handled by
// a session's outbound writer. A sum type keeps each case distinct.
type OutboundMessage = OutboundBatch | OutboundDisconnect | OutboundPacket

// EnqueueResult is what try_enqueue reports back, other than an outright
// error. enqueued needs no action. queue_full is a real overflow and
// aborts the session. closing means a disconnect (or an earlier overflow)
// is already underway, so this packet is dropped quietly instead of
// triggering a second abort that would cut the graceful drain short.
enum EnqueueResult {
	enqueued
	queue_full
	closing
}

// activate_outbound transfers transport writes from the bootstrap sequence
// to the session's outbound writer. It must run before the session is
// registered with a world or added to Hub.
//
// Returns false if the session is already closing. Repeated calls, including
// calls for test sessions that never entered bootstrap, are harmless.
pub fn (mut s NetworkSession) activate_outbound() bool {
	s.close_mutex.lock()
	if s.close_started {
		s.close_mutex.unlock()
		return false
	}
	if !s.outbound_bootstrap {
		s.close_mutex.unlock()
		return true
	}
	s.outbound_bootstrap = false
	s.close_mutex.unlock()
	s.ensure_outbound_writer()
	return true
}

// ensure_outbound_writer starts the session's writer the first time it is
// needed. The lock stops concurrent callers from starting duplicates,
// including sessions built directly in tests.
fn (mut s NetworkSession) ensure_outbound_writer() {
	s.writer_mutex.lock()
	if s.writer_started {
		s.writer_mutex.unlock()
		return
	}
	s.writer_started = true
	s.writer_mutex.unlock()
	spawn s.run_outbound_writer()
}

// try_enqueue adds an outbound message without blocking. Calling it before
// activate_outbound is an architecture error; callers that can return errors
// propagate it, while deliver and disconnect panic.
//
// The activation check, closing check, disconnect state change and enqueue
// are performed under one lock so nothing can be queued after a disconnect.
fn (mut s NetworkSession) try_enqueue(msg OutboundMessage, is_disconnect bool) !EnqueueResult {
	s.close_mutex.lock()
	if s.outbound_bootstrap {
		s.close_mutex.unlock()
		return error('outbound message enqueued before activate_outbound()')
	}
	if s.outbound_closing || s.close_started {
		s.close_mutex.unlock()
		return .closing
	}
	if is_disconnect {
		s.outbound_closing = true
	}
	s.ensure_outbound_writer()
	mut result := EnqueueResult.queue_full
	select {
		s.outbound <- msg {
			result = .enqueued
		}
		else {
			result = .queue_full
		}
	}
	s.close_mutex.unlock()
	if result == .queue_full {
		s.log.warn('outbound queue full (capacity ${outbound_queue_capacity}) for ${s.player.name()}, aborting session')
	}
	return result
}

// deliver queues a packet for the session's writer. If the queue is full,
// the session is aborted instead of blocking or silently dropping it. A
// packet arriving after the session already started closing is dropped
// quietly, with no second abort.
pub fn (mut s NetworkSession) deliver(p protocol.Packet) {
	result := s.try_enqueue(OutboundPacket{
		packet: p
	}, false) or { panic('deliver() called before activate_outbound(): ${err}') }
	if result == .queue_full {
		s.abort_outbound()
	}
}

// send_packet queues p for the session's outbound writer. It fails before
// activation, aborts on a full queue and ignores sends after closing begins.
pub fn (mut s NetworkSession) send_packet(p protocol.Packet) ! {
	result := s.try_enqueue(OutboundPacket{
		packet: p
	}, false)!
	match result {
		.enqueued {}
		.queue_full {
			s.abort_outbound()
			return error('session closing, packet dropped')
		}
		.closing {
			return error('session already closing, packet dropped')
		}
	}
}

// send_batch queues packets as one batch so concurrent sends can't split
// them apart. The slice is cloned because callers such as chunk streaming
// may reuse its backing storage before the writer sends it.
pub fn (mut s NetworkSession) send_batch(packets []protocol.Packet) ! {
	result := s.try_enqueue(OutboundBatch{
		packets: packets.clone()
	}, false)!
	match result {
		.enqueued {}
		.queue_full {
			s.abort_outbound()
			return error('session closing, batch dropped')
		}
		.closing {
			return error('session already closing, batch dropped')
		}
	}
}

// These helpers handle packets that may be sent before player initialization.
// They write directly during bootstrap and use the outbound queue after
// activation.
//
// The bootstrap check and direct write share one lock so activation cannot
// hand the transport to the writer while a direct send is still in progress.
fn (mut s NetworkSession) send_maybe_queued(p protocol.Packet) ! {
	s.close_mutex.lock()
	if s.outbound_bootstrap {
		s.transport.send(p) or {
			s.close_mutex.unlock()
			return err
		}
		s.close_mutex.unlock()
		return
	}
	s.close_mutex.unlock()
	s.send_packet(p)!
}

// send_batch_maybe_queued mirrors send_maybe_queued's locking. See its
// comment for why the bootstrap check and the direct write share one lock.
fn (mut s NetworkSession) send_batch_maybe_queued(packets []protocol.Packet) ! {
	s.close_mutex.lock()
	if s.outbound_bootstrap {
		s.transport.send_batch(packets) or {
			s.close_mutex.unlock()
			return err
		}
		s.close_mutex.unlock()
		return
	}
	s.close_mutex.unlock()
	s.send_batch(packets)!
}

// mark_closed moves the session into its closed state. Repeated calls are
// harmless; transport shutdown and writer completion are handled
// separately.
fn (mut s NetworkSession) mark_closed() {
	s.state = .closed
}

// close_outbound_once closes the transport and signals completion exactly
// once. It also wakes an idle writer so the thread cannot remain blocked
// on an empty queue after shutdown.
fn (mut s NetworkSession) close_outbound_once() {
	s.close_mutex.lock()
	if s.close_started {
		s.close_mutex.unlock()
		return
	}
	s.close_started = true
	s.close_mutex.unlock()
	s.transport.close()
	select {
		s.outbound_abort <- true {}
		else {}
	}
	s.outbound_done <- true
}

// abort_outbound closes the session immediately without touching the
// outbound queue. Used when delivery can no longer continue safely.
fn (mut s NetworkSession) abort_outbound() {
	s.mark_closed()
	s.close_outbound_once()
}

// reject_bootstrap closes sessions that fail before outbound activation,
// when packets still use direct transport writes. After activation, it
// delegates to the normal queued disconnect path.
fn (mut s NetworkSession) reject_bootstrap(message string) {
	s.close_mutex.lock()
	bootstrapping := s.outbound_bootstrap
	s.close_mutex.unlock()
	if !bootstrapping {
		s.disconnect(message)
		return
	}
	s.transport.send(&protocol.DisconnectPacket{
		reason:           0
		message:          message
		filtered_message: ''
	}) or {}
	s.abort_outbound()
}

// run_outbound_writer sends queued messages in order and handles socket
// writes away from the calling thread. An abort may interrupt the queue
// immediately including while the writer is idle.
fn (mut s NetworkSession) run_outbound_writer() {
	defer {
		select {
			s.writer_exited <- true {}
			else {}
		}
	}
	for {
		select {
			msg := <-s.outbound {
				match msg {
					OutboundPacket {
						s.transport.send(msg.packet) or {
							s.log.debug('outbound write failed: ${err}')
							s.abort_outbound()
							return
						}
					}
					OutboundBatch {
						s.transport.send_batch(msg.packets) or {
							s.log.debug('outbound batch write failed: ${err}')
							s.abort_outbound()
							return
						}
					}
					OutboundDisconnect {
						s.transport.send(&protocol.DisconnectPacket{
							reason:           0
							message:          msg.message
							filtered_message: ''
						}) or {}
						s.abort_outbound()
						return
					}
				}
			}
			_ := <-s.outbound_abort {
				return
			}
		}
	}
}
