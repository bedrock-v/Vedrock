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
	spawn srv.run()
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
}
