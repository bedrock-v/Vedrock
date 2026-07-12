module server

import os
import rand
import time
import server.cmd
import raknet
import protocol
import server.internal.logger
import server.internal.language
import server.conf
import server.internal.network
import server.session
import server.internal.gamedata
import server.world.db
import server.resource
import server.permission
import sync.stdatomic

pub const ticks_per_second = 20
pub const day_length_ticks = 24000
pub const worlds_dir = 'worlds'

// load_worlds always loads the configured default world, plus every other
// world found under worlds/ when load-all-worlds is enabled.
fn load_worlds(mut hub session.Hub, cfg conf.Config, log &logger.Logger) {
	mut names := [cfg.default_world]
	if cfg.load_all_worlds {
		for name in db.discover_worlds(worlds_dir) {
			if name !in names {
				names << name
			}
		}
	}
	for name in names {
		if w := db.load_named(worlds_dir, name, cfg.generator) {
			hub.add_world(w)
			log.info('Loaded world "${name}" (${w.block_count()} overrides)')
		} else {
			log.warn('Failed to load world "${name}": ${err}')
		}
	}
	if _ := hub.world(cfg.default_world) {
		hub.set_default_world(cfg.default_world)
	}
	if hub.world_count() == 0 {
		log.warn('No worlds loaded - players will spawn in an empty void')
	}
}

pub struct Server {
mut:
	listener &raknet.Listener = unsafe { nil }
	hub      &session.Hub     = unsafe { nil }
	guid     i64
	running    &stdatomic.AtomicVal[bool] = stdatomic.new_atomic[bool](false)
	created_at time.Time
pub mut:
	log  &logger.Logger
	lang &language.Lang
	cfg  conf.Config
}

// load_resource_packs builds the shared pack registry from local pack files and
// configured CDN packs. Returns an empty registry when disabled.
fn load_resource_packs(cfg conf.Config, log &logger.Logger) &resource.PackRegistry {
	mut reg := &resource.PackRegistry{}
	if !cfg.resource_packs {
		return reg
	}
	for name in resource.discover(cfg.resource_packs_dir) {
		path := os.join_path(cfg.resource_packs_dir, name)
		if pack := resource.new_local_pack(path) {
			reg.add(pack)
			log.info('Loaded resource pack ${pack.uuid} v${pack.version} (${pack.size} bytes)')
		} else {
			log.warn('Failed to load resource pack ${name}: ${err}')
		}
	}
	for pack in resource.parse_cdn_packs(cfg.cdn_packs) {
		reg.add(pack)
		log.info('Registered CDN resource pack ${pack.uuid} v${pack.version}')
	}
	reg.set_must_accept(cfg.force_resource_packs || !cfg.allow_client_packs)
	if reg.packs.len > 0 {
		log.info('Resource packs ready: ${reg.packs.len} pack(s), must_accept=${reg.must_accept}')
	}
	return reg
}

pub fn new(cfg conf.Config) &Server {
	boot_start := time.now()
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
	perm_cfg := permission.load_permissions_config(permission.default_permissions_file) or {
		log.warn('Failed to load permissions config: ${err}')
		permission.PermissionsConfig{}
	}
	for cmd_name in perm_cfg.disabled_commands {
		hub.commands.unregister(cmd_name)
		log.info('Command "${cmd_name}" disabled via ${permission.default_permissions_file}')
	}
	hub.player_grants = permission.load_player_grants(permission.default_player_permissions_file) or {
		log.warn('Failed to load player permissions file: ${err}')
		permission.PlayerGrants{}
	}
	hub.whitelist = permission.load_whitelist(permission.default_whitelist_file) or {
		log.warn('Failed to load whitelist: ${err}')
		permission.Whitelist{}
	}
	load_worlds(mut hub, cfg, log)
	hub.packs = load_resource_packs(cfg, log)
	return &Server{
		log:        log
		lang:       lang
		cfg:        cfg
		hub:        hub
		guid:       rand.i64()
		created_at: boot_start
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
	elapsed := (time.now() - s.created_at).seconds()
	s.log.info('Started successfully! Type /help for available commands. (${elapsed:.6f}s)')
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
		ctx := cmd.Context{
			lang:           s.lang
			sender_name:    sender.name()
			player_count:   s.hub.count()
			max_players:    s.cfg.max_players
			server_motd:    s.cfg.motd
			uptime_seconds: s.hub.uptime_seconds()
			tps:            s.hub.tps()
			load:           s.hub.load()
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
	// Carried between ticks so every TickJob has a meaningful value, even on
	// the 19 out of 20 ticks that don't recompute the window.
	mut tps := f64(ticks_per_second)
	mut load := f64(0)
	for s.running.load() {
		tick_start := time.now()
		tick++
		world_time := int(tick % day_length_ticks)
		if tick % u64(ticks_per_second) == 0 {
			s.hub.broadcast(&protocol.SetTimePacket{
				time: world_time
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
			tps = f64(window_ticks) / seconds
			load = f64(window_work) / f64(elapsed.nanoseconds()) * 100.0
			window_start = time.now()
			window_ticks = 0
			window_work = 0
		}
		// world_time/tps/load are Hub's, not tick_loop's own. This is the
		// only place that writes them via the actor.
		s.hub.submit(session.TickJob{
			world_time: world_time
			tps:        tps
			load:       load
		})
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
	label := match name.to_lower() {
		'survival' { 'Survival' }
		'adventure' { 'Adventure' }
		'spectator' { 'Spectator' }
		else { 'Creative' }
	}
	// The real gamemode is set separately via StartGamePacket.player_game_mode in spawn.v.
	return label, 1
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
