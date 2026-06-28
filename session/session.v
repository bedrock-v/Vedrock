module session

import network
import auth
import src as protocol
import src.enums
import logger
import config

pub enum State {
	handshake
	login
	play
	closed
}

@[heap]
pub struct NetworkSession {
mut:
	transport &network.Session = unsafe { nil }
	state     State            = .handshake
	cfg       config.Config
	identity  auth.Identity
pub mut:
	log &logger.Logger = unsafe { nil }
}

pub fn new(mut transport network.Session, cfg config.Config, log &logger.Logger) &NetworkSession {
	return &NetworkSession{
		transport: transport
		cfg:       cfg
		log:       log
	}
}

pub fn (mut s NetworkSession) handle_loop() {
	for s.state != .closed {
		packets := s.transport.read() or {
			s.log.debug('Connection ${s.transport.remote_addr()} ended: ${err}')
			break
		}
		for p in packets {
			s.handle(p) or {
				s.log.warn('Failed to handle ${p.name()}: ${err}')
				s.disconnect('Internal server error')
				break
			}
		}
	}
	s.transport.close()
}

fn (mut s NetworkSession) handle(p protocol.Packet) ! {
	match s.state {
		.handshake {
			if p is protocol.RequestNetworkSettingsPacket {
				s.handle_request_network_settings(p)!
			}
		}
		.login {
			if p is protocol.LoginPacket {
				s.handle_login(p)!
			}
		}
		else {}
	}
}

fn (mut s NetworkSession) handle_request_network_settings(p protocol.RequestNetworkSettingsPacket) ! {
	s.log.debug('Client requested network settings (protocol ${p.protocol_version})')
	settings := &protocol.NetworkSettingsPacket{
		compression_threshold:     s.cfg.compression_threshold
		compression_algorithm:     int(network.compression_zlib)
		enable_client_throttling:  false
		client_throttle_threshold: 0
		client_throttle_scalar:    0.0
	}
	s.transport.send(settings)!
	s.transport.enable_compression(s.cfg.compression_threshold)
	s.state = .login
}

fn (mut s NetworkSession) handle_login(p protocol.LoginPacket) ! {
	identity := auth.parse_login_chain(p.auth_info_json, s.cfg.xbox_auth) or {
		s.log.warn('Authentication failed: ${err}')
		s.disconnect('Login failed: ${err}')
		return
	}
	s.identity = identity
	mode := if identity.xbox_authenticated { 'Xbox Live' } else { 'offline' }
	s.log.info('${identity.display_name} authenticated [${mode}] xuid=${identity.xuid} uuid=${identity.uuid}')
	s.transport.send(&protocol.PlayStatusPacket{
		status: int(enums.PlayStatus.login_success)
	})!
	s.state = .play
}

pub fn (mut s NetworkSession) disconnect(message string) {
	s.transport.send(&protocol.DisconnectPacket{
		reason:           0
		message:          message
		filtered_message: ''
	}) or {}
	s.state = .closed
}
