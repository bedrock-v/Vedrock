module network

import sync
import time
import bedrock_v.webrtc.ice

// Status is what a client is told about a server before it joins. A listener
// needs it to answer a query. Whatever else goes in that answer is the
// listener's own business.
pub struct Status {
pub:
	motd        string = 'Vedrock'
	sub_motd    string = 'Vedrock'
	max_players int    = 20
	// network_id is the id NetherNet signalling knows this server by.
	network_id u64
}

// Listener accepts clients. NetherNetListener is the one that reaches the
// network. Tests stand in their own.
pub interface Listener {
	// accept takes the next client, waiting up to timeout for one. It fails when
	// none arrived.
mut:
	accept(timeout time.Duration) !Wire
	// announce sets the player count a client sees before it joins.
	announce(online int)
	// addr is where the listener is bound, for logs and messages.
	addr() string
	close()
}

// ListenerContext is what the server shares with every listener it builds.
//
// The server owns it, so anything listeners share is opened once and closed
// once, by the server. A listener that never asks for the media port leaves it
// unbound.
//
// It also holds who is admitted. A client takes a player slot when it arrives,
// on whichever listener, thus, the count every listener tells clients and checks
// against max_players is one count.
@[heap]
pub struct ListenerContext {
pub:
	status Status
	// media_port is the UDP port every NetherNet connection shares through one
	// mux whatever the number of listeners. Zero lets each connection take a
	// port the kernel picks.
	media_port u16
mut:
	mux ?&ice.UdpMux
	// listeners are told the player count whenever it changes.
	listeners []Listener
	players   int
	mu        &sync.Mutex = sync.new_mutex()
	// announcing orders what listeners are told. The count is read inside it
	// and the last announcement to run is the one that read the current count.
	announcing &sync.Mutex = sync.new_mutex()
}

// media returns the mux on media_port, binding it the first time a listener
// asks. Binding fails when the port is taken: falling back to another port
// would put the server somewhere the firewall rules don't cover.
pub fn (mut c ListenerContext) media() !&ice.UdpMux {
	if mux := c.mux {
		return mux
	}
	mux := ice.UdpMux.new(port: c.media_port) or {
		return error('media port ${c.media_port}: ${err}')
	}
	c.mux = mux
	return mux
}

// close closes the mux, once every listener and connection using it is gone.
pub fn (mut c ListenerContext) close() {
	if mut mux := c.mux {
		mux.close()
	}
}

// reserve_slot takes one of the player slots or reports that there is none
// left. Taking it under the same lock that holds the count is what keeps two
// clients arriving together from both getting the last one.
pub fn (mut c ListenerContext) reserve_slot() bool {
	c.mu.lock()
	if c.status.max_players > 0 && c.players >= c.status.max_players {
		c.mu.unlock()
		return false
	}
	c.players++
	c.mu.unlock()
	c.announce()
	return true
}

// free_slot gives back a slot reserve_slot took.
pub fn (mut c ListenerContext) free_slot() {
	c.mu.lock()
	c.players--
	c.mu.unlock()
	c.announce()
}

// player_count is how many slots are taken by players and by clients still
// logging in.
pub fn (mut c ListenerContext) player_count() int {
	c.mu.lock()
	defer {
		c.mu.unlock()
	}
	return c.players
}

fn (mut c ListenerContext) add_listener(listener Listener) {
	c.mu.lock()
	c.listeners << listener
	c.mu.unlock()
}

// announce tells every listener how many slots are taken.
fn (mut c ListenerContext) announce() {
	c.announcing.lock()
	defer {
		c.announcing.unlock()
	}
	c.mu.lock()
	online := c.players
	mut listeners := c.listeners.clone()
	c.mu.unlock()
	for mut listener in listeners {
		listener.announce(online)
	}
}

// ListenerFn builds a listener once the server knows what to tell clients.
pub type ListenerFn = fn (mut ctx ListenerContext) !Listener
