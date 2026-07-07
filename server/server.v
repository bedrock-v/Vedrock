module server

import os
import rand
import time
import command
import raknet
import protocol
import logger
import language
import config
import network
import session
import gamedata
import storage
import permission
import sync.stdatomic

pub const ticks_per_second = 20
pub const day_length_ticks = 24000

pub struct Server {
mut:
	listener &raknet.Listener = unsafe { nil }
	hub      &session.Hub     = unsafe { nil }
	guid     i64
	running  &stdatomic.AtomicVal[bool] = stdatomic.new_atomic[bool](false)
pub mut:
	log  &logger.Logger
	lang &language.Lang
	cfg  config.Config
}

pub fn new(cfg config.Config) &Server {
	mut level := logger.Level.info
	if cfg.debug {
		level = .debug
	}
	log := logger.new(level)
	lang := language.load(cfg.language) or {
		log.warn('Failed to load language "${cfg.language}", falling back to en: ${err}')
		language.load('en') or {
			log.error('Failed to load fallback language: ${err}')
			panic(err)
		}
	}
	data := gamedata.load('data') or {
		log.warn('Failed to load game data from ./data: ${err}')
		gamedata.GameData{}
	}
	log.info('Loaded ${data.item_entries.len} items and ${data.creative_items.len} creative entries')
	mut hub := session.new_hub(data)
	hub.lang = lang
	hub.ops = permission.load_ops(permission.default_ops_file) or {
		log.warn('Failed to load ops file: ${err}')
		permission.OpList{}
	}
	if store := storage.open_world('worlds/world/db') {
		hub.world_store = store
		hub.load_world()
		log.info('Loaded world with ${hub.world_block_count()} stored block changes')
	} else {
		log.warn('Failed to open world database: ${err}')
	}
	return &Server{
		log:  log
		lang: lang
		cfg:  cfg
		hub:  hub
		guid: rand.i64()
	}
}

pub fn (mut s Server) start() ! {
	// s.log.info('Starting Vedrock for Minecraft Bedrock ${protocol.minecraft_version_network} (protocol ${protocol.current_protocol})')
	s.log.info(s.lang.tf('server.starting', {
		'Version':  protocol.minecraft_version_network
		'Protocol': protocol.current_protocol.str()
	}))
	mut listener := raknet.listen(s.cfg.bind_address())!
	listener.set_pong_data(s.pong_data(0).bytes())!
	s.listener = listener
	s.running.store(true)
	s.log.info('Listening on ${s.cfg.bind_address()}')
	spawn s.tick_loop()
	spawn s.console_loop()
	s.accept_loop()
}

const console_poll_interval = 100 * time.millisecond

// console_loop reads command lines from stdin and dispatches them through the
// shared command registry as CONSOLE, mirroring the in-game chat path.
fn (mut s Server) console_loop() {
	mut sender := session.new_console_sender(mut s.hub, s.log)
	for s.running.load() {
		if !os.fd_is_pending(0) {
			time.sleep(console_poll_interval)
			continue
		}
		raw := os.get_raw_line()
		if raw.len == 0 {
			// stdin reached EOF (e.g. running detached); stop polling.
			return
		}
		line := raw.trim_space()
		if line == '' {
			continue
		}
		ctx := command.Context{
			lang:           s.lang
			sender_name:    sender.name()
			player_count:   s.hub.count()
			max_players:    s.cfg.max_players
			server_motd:    s.cfg.motd
			uptime_seconds: s.hub.uptime_seconds()
			tps:            s.hub.tps
			load:           s.hub.load
		}
		s.hub.commands.dispatch(line, mut sender, ctx) or {
			s.log.error('Console command failed: ${err}')
		}
	}
}

fn (mut s Server) tick_loop() {
	interval := time.second / ticks_per_second
	loop_start := time.now()
	mut tick := u64(0)
	mut window_start := time.now()
	mut window_ticks := 0
	mut window_work := i64(0)
	for s.running.load() {
		tick_start := time.now()
		tick++
		s.hub.world_time = int((tick % day_length_ticks))
		if tick % u64(ticks_per_second) == 0 {
			s.hub.broadcast(&protocol.SetTimePacket{
				time: s.hub.world_time
			})
			s.listener.set_pong_data(s.pong_data(s.hub.count()).bytes()) or {
				s.log.warn('Failed to update pong data: ${err}')
			}
		}
		work := time.now() - tick_start
		window_ticks++
		window_work += work.nanoseconds()
		elapsed := time.now() - window_start
		if elapsed >= time.second {
			seconds := f64(elapsed.nanoseconds()) / f64(time.second)
			s.hub.tps = f64(window_ticks) / seconds
			s.hub.load = f64(window_work) / f64(elapsed.nanoseconds()) * 100.0
			window_start = time.now()
			window_ticks = 0
			window_work = 0
		}
		deadline := loop_start.add(time.Duration(i64(interval) * i64(tick)))
		sleep_for := deadline - time.now()
		if sleep_for > 0 {
			time.sleep(sleep_for)
		}
	}
}

fn (mut s Server) accept_loop() {
	for s.running.load() {
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
	return
		['MCPE', s.cfg.motd, protocol.current_protocol.str(), protocol.minecraft_version_network, online.str(), s.cfg.max_players.str(), s.guid.str(), s.cfg.sub_motd, gamemode, gamemode_num.str(), s.cfg.port.str(), s.cfg.port.str()].join(';') +
		';'
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
	if !s.running.load() {
		return
	}
	s.log.info('Stopping server')
	s.running.store(false)
	if s.hub != unsafe { nil } {
		s.hub.disconnect_all('Server closed')
	}
	if s.listener != unsafe { nil } {
		s.listener.close() or {}
	}
}
