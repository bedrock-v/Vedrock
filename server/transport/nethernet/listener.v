module nethernet

import time
import bedrock_v.protocol
import bedrock_v.nethernet as nn
import bedrock_v.nethernet.endpoint
import server.net

// Config is what a NetherNet listener needs that no other transport does.
pub struct Config {
pub:
	// address is the interface the signalling endpoint binds.
	address string = '0.0.0.0'
	port    int    = 19132
	// identity_file holds the key the server answers under, created on the
	// first start. Keeping it means a client that remembers this server keeps
	// recognising it.
	identity_file string = 'identity.key'
	// allow_anonymous accepts an offer carrying no identity assertion. The game
	// leaves the assertion out of most of its offers, and refusing those would
	// refuse most clients.
	allow_anonymous bool = true
}

// listener builds a NetherNet listener for a server's Config.listeners.
pub fn listener(cfg Config) net.ListenerFn {
	return fn [cfg] (status net.Status) !net.Listener {
		return listen(cfg, status)!
	}
}

// Listener accepts NetherNet clients.
//
// NetherNet negotiates nothing without a signalling channel first. This binds
// the HTTP one, which is what a client uses when it joins by address.
pub struct Listener {
	cfg    Config
	status net.Status
mut:
	signalling &endpoint.EndpointHandler
	inner      &nn.Listener
}

// listen binds the signalling endpoint and the connection listener over it.
pub fn listen(cfg Config, status net.Status) !&Listener {
	mut signalling := endpoint.listen(
		address:    '${cfg.address}:${cfg.port}'
		network_id: status.network_id.str()
	)!
	signalling.pong_data(pong_data(cfg, status, 0).bytes())
	mut inner := nn.listen(mut signalling,
		identity:        load_identity(cfg.identity_file)!
		allow_anonymous: cfg.allow_anonymous
	) or {
		signalling.close()
		return err
	}
	return &Listener{
		cfg:        cfg
		status:     status
		signalling: signalling
		inner:      inner
	}
}

// accept takes the next client connection, waiting up to timeout for one.
pub fn (mut l Listener) accept(timeout time.Duration) !net.Wire {
	mut conn := l.inner.accept(timeout)!
	return &Wire{
		conn: conn
	}
}

// announce updates the player count a client sees before it joins.
pub fn (mut l Listener) announce(online int) {
	l.signalling.pong_data(pong_data(l.cfg, l.status, online).bytes())
}

// addr is where the listener is bound.
pub fn (l &Listener) addr() string {
	return '${l.cfg.address}:${l.cfg.port}'
}

pub fn (mut l Listener) close() {
	l.inner.close()
	l.signalling.close()
}

// pong_data is the server description a client reads before it joins. The
// fields are semicolon separated, the way the game has written them since this
// was a LAN broadcast.
fn pong_data(cfg Config, status net.Status, online int) string {
	fields := ['MCPE', status.motd, protocol.protocol_id.str(), protocol.minecraft_version,
		online.str(), status.max_players.str(), status.network_id.str(), status.sub_motd, 'Survival',
		'1', cfg.port.str(), cfg.port.str()]
	// The 1 after 'Survival' is availability, not gamemodeId.
	return fields.join(';') + ';'
}

// Wire is a NetherNet connection as whole messages in and out.
pub struct Wire {
mut:
	conn &nn.Conn
}

pub fn (mut w Wire) read_message() ![]u8 {
	return w.conn.read_packet()!
}

pub fn (mut w Wire) write_message(b []u8) ! {
	_ := w.conn.write(b)!
}

pub fn (mut w Wire) remote() string {
	return remote_endpoint(w.conn.remote_addr())
}

pub fn (mut w Wire) encrypted() bool {
	return w.conn.disable_encryption()
}

pub fn (mut w Wire) close() {
	w.conn.close()
}

// remote_endpoint renders an address as the peer's "ip:port", read out of the
// ICE candidate the connection settled on. Addr.str() carries the network id,
// the connection id and the whole candidate line, none of which says anything
// in a game log.
fn remote_endpoint(addr nn.Addr) string {
	fields := addr.selected_candidate.split(' ')
	typ := fields.index('typ')
	if typ >= 2 {
		return '${fields[typ - 2]}:${fields[typ - 1]}'
	}
	return addr.str()
}
