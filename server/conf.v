module server

import server.network

// Config is a server's settings.
pub struct Config {
pub:
	// listeners are what this server accepts clients on, one function each,
	// called when the server starts.
	//
	// A server with none accepts nobody and there is no default.
	listeners []network.ListenerFn
	motd      string = 'Vedrock'
	sub_motd  string = 'Vedrock'
	// max_players is how many players are admitted at once, and what a client is
	// told before it joins. A client takes a slot when it arrives. This also
	// bounds how many can be logging in. Zero admits any number.
	max_players int = 20
	// network_id is the id NetherNet signalling knows this server by.
	network_id u64
	// media_port is the UDP port every player's connection runs over, the one a
	// firewall has to let through. The server fails to start when it is taken.
	// Zero gives each connection a port the kernel picks.
	media_port u16 = 19133
	// world_name names the world players join.
	world_name string = 'world'
	login      network.LoginConfig
}

// status is what every listener tells a client before it joins. One server
// describes itself one way, whichever listener is answering.
fn (cfg &Config) status() network.Status {
	return network.Status{
		motd:        cfg.motd
		sub_motd:    cfg.sub_motd
		max_players: cfg.max_players
		network_id:  cfg.network_id
	}
}
