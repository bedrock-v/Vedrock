module network

import time
import bedrock_v.nethernet as nn
import bedrock_v.nethernet.discovery

// LanConfig is what the LAN listener needs to bind.
pub struct LanConfig {
pub:
	address string = '0.0.0.0'
	// port is where the game looks for LAN games. Every server on a host shares
	// it, so only one of them can be seen on the LAN.
	port            int    = discovery.default_port
	identity_file   string = 'keys/server_identity_key.pem'
	identity_domain string
	// allow_anonymous accepts an offer carrying no identity assertion. The game
	// never signs the offers it broadcasts on the LAN and refusing them would
	// refuse every LAN client.
	allow_anonymous bool = true
}

// lan builds a listener that shows the server in the game's list of LAN games
// for a server's Config.listeners.
pub fn lan(cfg LanConfig) ListenerFn {
	return fn [cfg] (status Status) !Listener {
		return listen_lan(cfg, status)!
	}
}

// LanListener accepts NetherNet clients that found the server on the LAN.
pub struct LanListener {
	cfg    LanConfig
	status Status
mut:
	signalling &discovery.Listener
	inner      &nn.Listener
}

// listen_lan binds the discovery socket and the connection listener over it.
pub fn listen_lan(cfg LanConfig, status Status) !&LanListener {
	identity := load_identity(cfg.identity_file, identity_domain(cfg.identity_domain, status))!
	// A server answers the game's broadcasts and never sends its own.
	mut signalling := discovery.listen('${cfg.address}:${cfg.port}',
		network_id: status.network_id
		broadcast:  false
	)!
	signalling.pong_data(pong_data(status, cfg.port, 0).bytes())
	mut inner := nn.listen(mut signalling,
		identity:        identity
		allow_anonymous: cfg.allow_anonymous
	) or {
		signalling.close()
		return err
	}
	return &LanListener{
		cfg:        cfg
		status:     status
		signalling: signalling
		inner:      inner
	}
}

pub fn (mut l LanListener) accept(timeout time.Duration) !Wire {
	mut conn := l.inner.accept(timeout)!
	return &NetherNetWire{
		conn: conn
	}
}

pub fn (mut l LanListener) announce(online int) {
	l.signalling.pong_data(pong_data(l.status, l.cfg.port, online).bytes())
}

pub fn (l &LanListener) addr() string {
	return '${l.cfg.address}:${l.cfg.port}'
}

pub fn (mut l LanListener) close() {
	l.inner.close()
	l.signalling.close()
}
