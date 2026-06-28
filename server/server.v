module server

import rand
import time
import raknet
import src as protocol
import logger
import config

pub struct Server {
mut:
	listener &raknet.Listener = unsafe { nil }
	guid     i64
	running  bool
pub mut:
	log &logger.Logger
	cfg config.Config
}

pub fn new(cfg config.Config) &Server {
	mut level := logger.Level.info
	if cfg.debug {
		level = .debug
	}
	return &Server{
		log:  logger.new(level)
		cfg:  cfg
		guid: rand.i64()
	}
}

pub fn (mut s Server) start() ! {
	s.log.info('Starting Vedrock for Minecraft Bedrock ${protocol.minecraft_version_network} (protocol ${protocol.current_protocol})')
	mut listener := raknet.listen(s.cfg.bind_address())!
	listener.set_pong_data(s.pong_data(0).bytes())
	s.listener = listener
	s.running = true
	s.log.info('Listening on ${s.cfg.bind_address()}')
	s.accept_loop()
}

fn (mut s Server) accept_loop() {
	for s.running {
		mut conn := s.listener.accept_timeout(time.second) or { continue }
		s.log.info('Incoming connection from ${conn.remote_addr()}')
		conn.close() or {}
	}
}

fn (s &Server) pong_data(online int) string {
	gamemode, gamemode_num := normalize_gamemode(s.cfg.gamemode)
	return [
		'MCPE',
		s.cfg.motd,
		protocol.current_protocol.str(),
		protocol.minecraft_version_network,
		online.str(),
		s.cfg.max_players.str(),
		s.guid.str(),
		s.cfg.sub_motd,
		gamemode,
		gamemode_num.str(),
		s.cfg.port.str(),
		s.cfg.port.str(),
	].join(';') + ';'
}

fn normalize_gamemode(name string) (string, int) {
	return match name.to_lower() {
		'survival' { 'Survival', 0 }
		'adventure' { 'Adventure', 2 }
		'spectator' { 'Spectator', 6 }
		else { 'Creative', 1 }
	}
}

pub fn (mut s Server) stop() {
	if !s.running {
		return
	}
	s.log.info('Stopping server')
	s.running = false
	if s.listener != unsafe { nil } {
		s.listener.close() or {}
	}
}
