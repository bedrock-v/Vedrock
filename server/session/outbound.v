module session

import bedrock_v.protocol
import bedrock_v.protocol.current as proto
import server.player

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
fn (mut s NetworkSession) activate_outbound() bool {
	return s.conn.activate(s.log)
}

// try_enqueue hands msg to the connection and reports an overflow against the
// player it belongs to. Conn has no gameplay state, so naming the player and
// finding the world runtime to count the overflow against happens here.
fn (mut s NetworkSession) try_enqueue(msg OutboundMessage, is_disconnect bool) !EnqueueResult {
	result := s.conn.enqueue(msg, is_disconnect, s.log)!
	if result == .queue_full {
		mut wr := s.current_world_runtime()
		if !isnil(wr) {
			wr.record_outbound_overflow()
		}
		s.log.warn('outbound queue full (capacity ${outbound_queue_capacity}) for ${s.player.name()}, aborting session')
	}
	return result
}

// deliver queues a packet for the session's writer. If the queue is full,
// the session is aborted instead of blocking or silently dropping it. A
// packet arriving after the session already started closing is dropped
// quietly, with no second abort.
fn (mut s NetworkSession) deliver(p protocol.Packet) {
	result := s.try_enqueue(OutboundPacket{
		packet: p
	}, false) or { panic('deliver() called before activate_outbound(): ${err}') }
	if result == .queue_full {
		s.abort_outbound()
	}
}

// send_packet queues p for the session's outbound writer. It fails before
// activation, aborts on a full queue and ignores sends after closing begins.
fn (mut s NetworkSession) send_packet(p protocol.Packet) ! {
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
fn (mut s NetworkSession) send_batch(packets []protocol.Packet) ! {
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
fn (mut s NetworkSession) send_maybe_queued(p protocol.Packet) ! {
	if s.conn.send_direct(p)! {
		return
	}
	s.send_packet(p)!
}

// send_batch_maybe_queued is send_maybe_queued for a batch.
fn (mut s NetworkSession) send_batch_maybe_queued(packets []protocol.Packet) ! {
	if s.conn.send_batch_direct(packets)! {
		return
	}
	s.send_batch(packets)!
}

// mark_closed moves the session into its closed state. Repeated calls are
// harmless; transport shutdown and writer completion are handled
// separately.
fn (mut s NetworkSession) mark_closed() {
	s.conn.state = .closed
}

// close_outbound_once closes the transport and signals completion exactly
// once. It also wakes an idle writer so the thread cannot remain blocked
// on an empty queue after shutdown.
fn (mut s NetworkSession) close_outbound_once() {
	s.conn.close_once()
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
	if !s.conn.bootstrapping() {
		s.disconnect(message)
		return
	}
	s.conn.send_direct(&proto.DisconnectPacket{
		reason:  proto.connection_fail_disconnect_packet
		message: proto.DisconnectMessage{
			kick_message:     message
			filtered_message: ''
		}
	}) or {}
	s.abort_outbound()
}
