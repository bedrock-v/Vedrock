module server

import server.net

// Config is a server's settings.
pub struct Config {
pub:
	// listeners are the transports this server accepts on, one function each,
	// called when the server starts.
	//
	// A server with none accepts nobody and there is no default.
	listeners []net.ListenerFn
	motd      string = 'Vedrock'
	sub_motd  string = 'Vedrock'
	// max_players is how many players are admitted at once, and what a client is
	// told before it joins. Zero admits any number.
	max_players int = 20
	// network_id names this server to a transport that needs an id of its own.
	network_id u64
	// world_name names the world players join.
	world_name string = 'world'
	login      net.LoginConfig
}

// status is what every listener tells a client before it joins. One server
// describes itself one way, whichever transport is answering.
fn (cfg &Config) status() net.Status {
	return net.Status{
		motd:        cfg.motd
		sub_motd:    cfg.sub_motd
		max_players: cfg.max_players
		network_id:  cfg.network_id
	}
}
