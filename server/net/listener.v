module net

import time

// Status is what a client is told about a server before it joins. A transport
// needs it to answer a query. Whatever else goes in that answer is the
// transport's own business.
pub struct Status {
pub:
	motd        string = 'Vedrock'
	sub_motd    string = 'Vedrock'
	max_players int    = 20
	// network_id names this server to a transport that needs an id of its own.
	network_id u64
}

// Listener accepts clients over one transport.
pub interface Listener {
	// accept takes the next client, waiting up to timeout for one. It fails when
	// none arrived, which is how a caller gets to look at whether it is still
	// running.
mut:
	accept(timeout time.Duration) !Wire
	// announce sets the player count a client sees before it joins.
	announce(online int)
	// addr is where the listener is bound, for logs and messages.
	addr() string
	close()
}

// ListenerFn builds a listener once the server knows what to tell clients.
pub type ListenerFn = fn (Status) !Listener
