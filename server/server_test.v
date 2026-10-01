module server

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
