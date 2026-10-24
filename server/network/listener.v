module network

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

// ListenerFn builds a listener once the server knows what to tell clients.
pub type ListenerFn = fn (mut ctx ListenerContext) !Listener
