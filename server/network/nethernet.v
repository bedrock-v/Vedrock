module network

import time
import bedrock_v.protocol
import bedrock_v.nethernet as nn
import bedrock_v.nethernet.endpoint

// NetherNetConfig is what the NetherNet listener needs to bind.
pub struct NetherNetConfig {
pub:
	// address is the interface the signalling endpoint binds.
	address string = '0.0.0.0'
	port    int    = 19132
	// identity_file holds the P-384 key the server answers under, as PEM. It is
	// created on the first start. Keeping it means a client that remembers this
	// server keeps recognising it.
	identity_file string = 'keys/server_identity_key.pem'
	// identity_domain is the domain the server's identity token names which a
	// client shows when asked to trust this server. Unset and the MOTD stands in.
	identity_domain string
	// allow_anonymous accepts an offer carrying no identity assertion. The game
	// leaves the assertion out of most of its offers and refusing those would
	// refuse most clients.
	allow_anonymous bool = true
}

// nethernet builds a NetherNet listener for a server's Config.listeners.
pub fn nethernet(cfg NetherNetConfig) ListenerFn {
	return fn [cfg] (status Status) !Listener {
		return listen(cfg, status)!
	}
}

// NetherNetListener accepts NetherNet clients.
pub struct NetherNetListener {
	cfg    NetherNetConfig
	status Status
mut:
	signalling &endpoint.EndpointHandler
	inner      &nn.Listener
}

// listen binds the signalling endpoint and the connection listener over it.
pub fn listen(cfg NetherNetConfig, status Status) !&NetherNetListener {
	identity := load_identity(cfg.identity_file, identity_domain(cfg.identity_domain, status))!
	mut signalling := endpoint.listen(
		address:    '${cfg.address}:${cfg.port}'
		network_id: status.network_id.str()
	)!
	signalling.pong_data(pong_data(status, cfg.port, 0).bytes())
	mut inner := nn.listen(mut signalling,
		identity:        identity
		allow_anonymous: cfg.allow_anonymous
	) or {
		signalling.close()
		return err
	}
	return &NetherNetListener{
		cfg:        cfg
		status:     status
		signalling: signalling
		inner:      inner
	}
}

fn identity_domain(configured string, status Status) string {
	if configured != '' {
		return configured
	}
	if status.motd != '' {
		return status.motd
	}
	return 'vedrock'
}

// accept takes the next client connection, waiting up to timeout for one.
pub fn (mut l NetherNetListener) accept(timeout time.Duration) !Wire {
	mut conn := l.inner.accept(timeout)!
	return &NetherNetWire{
		conn: conn
	}
}

// announce updates the player count a client sees before it joins.
pub fn (mut l NetherNetListener) announce(online int) {
	l.signalling.pong_data(pong_data(l.status, l.cfg.port, online).bytes())
}

// addr is where the listener is bound.
pub fn (l &NetherNetListener) addr() string {
	return '${l.cfg.address}:${l.cfg.port}'
}

pub fn (mut l NetherNetListener) close() {
	l.inner.close()
	l.signalling.close()
}

// pong_data is the server description a client reads before it joins.
fn pong_data(status Status, port int, online int) string {
	fields := ['MCPE', status.motd, protocol.protocol_id.str(), protocol.minecraft_version,
		online.str(), status.max_players.str(), status.network_id.str(), status.sub_motd, 'Survival',
		'1', port.str(), port.str()]
	// The 1 after 'Survival' is availability, not gamemodeId.
	return fields.join(';') + ';'
}

// NetherNetWire is a NetherNet connection as whole messages in and out.
struct NetherNetWire {
mut:
	conn &nn.Conn
}

pub fn (mut w NetherNetWire) read_message() ![]u8 {
	return w.conn.read_packet()!
}

pub fn (mut w NetherNetWire) write_message(b []u8) ! {
	_ := w.conn.write(b)!
}

pub fn (mut w NetherNetWire) remote() string {
	return remote_endpoint(w.conn.remote_addr())
}

pub fn (mut w NetherNetWire) close() {
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
