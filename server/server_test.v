module server

import sync
import time
import server.net

// CloseCount is shared with the listeners a test builds, so a test can see one
// being closed.
struct CloseCount {
mut:
	n int
}

// FakeListener is a listener that binds nothing and accepts nobody. A test only
// needs it to exist and to say when it was closed.
struct FakeListener {
mut:
	closes &CloseCount
}

fn (mut l FakeListener) accept(timeout time.Duration) !net.Wire {
	return error('no client arrived')
}

fn (mut l FakeListener) announce(online int) {}

fn (l &FakeListener) addr() string {
	return 'fake'
}

fn (mut l FakeListener) close() {
	l.closes.n++
}

fn binds(closes &CloseCount) net.ListenerFn {
	return fn [closes] (status net.Status) !net.Listener {
		return &FakeListener{
			closes: unsafe { closes }
		}
	}
}

fn refuses_to_bind() net.ListenerFn {
	return fn (status net.Status) !net.Listener {
		return error('this transport could not bind')
	}
}

fn test_a_server_with_no_listeners_is_refused() {
	if _ := new(Config{}) {
		assert false, 'a server that can accept nobody was started'
	}
}

fn test_a_listener_that_cant_bind_closes_ones_already_bound() {
	mut closes := &CloseCount{}
	if _ := new(Config{
		listeners: [binds(closes), refuses_to_bind(), binds(closes)]
	})
	{
		assert false, 'a server started with a listener that could not bind'
	}
	assert closes.n == 1, 'the listener bound before the failure was not closed'
}

// BlockingWire is a client that connects and then says nothing, which is where
// a connection spends its time while it is logging in.
struct BlockingWire {
mut:
	unblock chan bool   = chan bool{}
	guard   &sync.Mutex = sync.new_mutex()
	reading bool
	closed  bool
}

fn (mut w BlockingWire) read_message() ![]u8 {
	w.guard.lock()
	w.reading = true
	w.guard.unlock()
	_ := <-w.unblock or { return error('the connection was closed') }
	return error('the connection was closed')
}

fn (mut w BlockingWire) write_message(b []u8) ! {
	if w.is_closed() {
		return error('the connection was closed')
	}
}

fn (mut w BlockingWire) remote() string {
	return 'blocking'
}

fn (mut w BlockingWire) encrypted() bool {
	return true
}

fn (mut w BlockingWire) close() {
	w.guard.lock()
	defer {
		w.guard.unlock()
	}
	if w.closed {
		return
	}
	w.closed = true
	w.unblock.close()
}

fn (mut w BlockingWire) is_closed() bool {
	w.guard.lock()
	defer {
		w.guard.unlock()
	}
	return w.closed
}

fn (mut w BlockingWire) is_reading() bool {
	w.guard.lock()
	defer {
		w.guard.unlock()
	}
	return w.reading
}

// OneClientListener hands out one wire and nothing after it.
struct OneClientListener {
mut:
	wire  &BlockingWire
	given bool
}

fn (mut l OneClientListener) accept(timeout time.Duration) !net.Wire {
	if l.given {
		return error('no client arrived')
	}
	l.given = true
	return l.wire
}

fn (mut l OneClientListener) announce(online int) {}

fn (l &OneClientListener) addr() string {
	return 'one'
}

fn (mut l OneClientListener) close() {}

fn gives(wire &BlockingWire) net.ListenerFn {
	return fn [wire] (status net.Status) !net.Listener {
		return &OneClientListener{
			wire: unsafe { wire }
		}
	}
}

fn test_closing_ends_a_connection_that_is_still_logging_in() {
	mut wire := &BlockingWire{}
	mut srv := new(Config{
		listeners: [gives(wire)]
	}) or { panic(err) }
	mut running := spawn srv.run()
	for _ in 0 .. 400 {
		if wire.is_reading() {
			break
		}
		time.sleep(5 * time.millisecond)
	}
	assert wire.is_reading(), 'the client was never read from'
	assert srv.player_count() == 0

	srv.close()
	assert wire.is_closed(), 'a connection still logging in was left open'
	assert srv.conns.len == 0, 'close returned while a client was still being handled'
	// run returns once the server is down, the last thing close does.
	running.wait()
}

// ManyClientListener hands out the wires it was given, one per accept.
struct ManyClientListener {
mut:
	wires []&BlockingWire
	next  int
}

fn (mut l ManyClientListener) accept(timeout time.Duration) !net.Wire {
	if l.next >= l.wires.len {
		return error('no client arrived')
	}
	l.next++
	return l.wires[l.next - 1]
}

fn (mut l ManyClientListener) announce(online int) {}

fn (l &ManyClientListener) addr() string {
	return 'many'
}

fn (mut l ManyClientListener) close() {}

fn gives_all(wires []&BlockingWire) net.ListenerFn {
	return fn [wires] (status net.Status) !net.Listener {
		return &ManyClientListener{
			wires: wires
		}
	}
}

fn reading(wires []&BlockingWire) int {
	mut n := 0
	for w in wires {
		mut wire := unsafe { w }
		if wire.is_reading() {
			n++
		}
	}
	return n
}

fn closed(wires []&BlockingWire) int {
	mut n := 0
	for w in wires {
		mut wire := unsafe { w }
		if wire.is_closed() {
			n++
		}
	}
	return n
}

fn test_only_so_many_clients_may_be_logging_in_at_once() {
	mut wires := []&BlockingWire{}
	for _ in 0 .. 6 {
		wires << &BlockingWire{}
	}
	mut srv := new(Config{
		listeners:   [gives_all(wires)]
		max_pending: 2
	}) or { panic(err) }
	spawn srv.run()
	mut settled := 0
	for _ in 0 .. 400 {
		settled = reading(wires)
		if settled + closed(wires) == wires.len {
			break
		}
		time.sleep(5 * time.millisecond)
	}
	assert settled == 2, 'the server took ${settled} logins at once'
	assert closed(wires) == 4, 'the clients over the limit were not refused'
	srv.close()
}

fn test_a_client_that_never_finishes_logging_in_is_dropped() {
	mut wire := &BlockingWire{}
	mut srv := new(Config{
		listeners:     [gives(wire)]
		login_timeout: 50 * time.millisecond
	}) or { panic(err) }
	spawn srv.run()
	mut dropped := false
	for _ in 0 .. 400 {
		if wire.is_closed() {
			dropped = true
			break
		}
		time.sleep(5 * time.millisecond)
	}
	srv.close()
	assert dropped, 'a client that never logged in was left connected'
}
