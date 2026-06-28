module server

import rand
import time
import raknet
import protocol
import logger
import config
import network
import session
import gamedata

pub const ticks_per_second = 20
pub const day_length_ticks = 24000

pub struct Server {
mut:
	listener &raknet.Listener = unsafe { nil }
	hub      &session.Hub     = unsafe { nil }
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
	log := logger.new(level)
	data := gamedata.load('data') or {
		log.warn('Failed to load game data from ./data: ${err}')
		gamedata.GameData{}
	}
	log.info('Loaded ${data.item_entries.len} items and ${data.creative_items.len} creative entries')
	return &Server{
		log:  log
		cfg:  cfg
		hub:  session.new_hub(data)
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
	spawn s.tick_loop()
	s.accept_loop()
}

fn (mut s Server) tick_loop() {
	interval := time.second / ticks_per_second
	mut tick := u64(0)
	for s.running {
		time.sleep(interval)
		tick++
		s.hub.world_time = int((tick % day_length_ticks))
		if tick % u64(ticks_per_second) == 0 {
			s.hub.broadcast(&protocol.SetTimePacket{
				time: s.hub.world_time
			})
			s.listener.set_pong_data(s.pong_data(s.hub.count()).bytes())
		}
	}
}

fn (mut s Server) accept_loop() {
	for s.running {
		mut conn := s.listener.accept_timeout(time.second) or { continue }
		s.log.info('Incoming connection from ${conn.remote_addr()}')
		spawn s.handle(mut conn)
	}
}

fn (mut s Server) handle(mut conn raknet.Conn) {
	mut transport := network.new_session(mut conn, s.log)
	mut net_session := session.new(mut transport, mut s.hub, s.cfg, s.log)
	net_session.handle_loop()
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
