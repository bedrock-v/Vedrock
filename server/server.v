module server

import os
import rand
import time
import server.cmd
import server.scheduler
import nethernet
import nethernet.discovery
import nethernet.endpoint
import server.internal.logger
import server.internal.language
import server.conf
import server.internal.network
import server.session
import server.internal.buildinfo
import server.internal.gamedata
import server.world
import server.resourcepack
import server.permission
import server.crash
import server.event
import server.player.playerdb
import sync.stdatomic
import protocol.current as proto
import webrtc.logging

// nethernet_identity_domain names the issuer of the server's identity token.
// Bedrock Dedicated Server self-signs its own the same way.
const nethernet_identity_domain = 'self'

pub const ticks_per_second = 20
pub const day_length_ticks = 24000
// tick_overrun_log_interval throttles the "tick over budget" warning so a slow
// stretch logs once per this many ticks instead of spamming every tick.
const tick_overrun_log_interval = u64(ticks_per_second) * 5

// world_flush_interval_ticks bounds how much placed/broken block data an
// ungraceful shutdown (crash, kill -9) can lose.
const world_flush_interval_ticks = u64(ticks_per_second) * 30

// persist_pressure_log_interval controls how often persistence backlog
// warnings may be logged while pressure remains elevated.
const persist_pressure_log_interval = u64(ticks_per_second) * 5

// heap_release_interval_ticks bounds how long freed memory stays mapped after a
// burst - a player leaving takes their chunk and session allocations with them.
const heap_release_interval_ticks = u64(ticks_per_second) * 300

fn C.GC_gcollect_and_unmap()

// release_free_heap collects and hands blocks the collector no longer needs
// back to the OS.
//
// Boehm keeps freed blocks mapped until they have been idle for several
// collections, so without this the process keeps resident whatever its peak
// was - and boot's peak is the block palette and item/creative JSON parses,
// several times what any of them actually retains.
fn release_free_heap() {
	C.GC_gcollect_and_unmap()
}

fn C.GC_get_heap_size() usize

fn C.GC_get_free_bytes() usize

// heap_summary reports the collector's mapped and live sizes, for the debug log
// that follows a heap release.
fn heap_summary() string {
	total := u64(C.GC_get_heap_size())
	free := u64(C.GC_get_free_bytes())
	return 'heap mapped=${total / 1024 / 1024}MB live=${(total - free) / 1024 / 1024}MB'
}

// Options is the framework's composition-root entry point. settings carries
// YAML-loadable server tuning; hub_options swaps Hub subsystems such as the
// command and entity registries. Every field left unset falls back to Vedrock's
// built-in default, so new() with no arguments still boots a working server.
@[params]
pub struct Options {
pub:
	settings    conf.Config
	hub_options session.HubOptions
}

// Server is the running instance returned by new(). Its hub remains
// private.
//
// Optional extension layers such as plugins may build on this public API;
// Server doesn't wire them in directly.
@[heap]
pub struct Server {
mut:
	hub &session.Hub = unsafe { nil }
	// signaling is the LAN discovery channel: the same socket advertises the
	// world and carries the offers and answers that negotiate a connection.
	signaling &discovery.Listener = unsafe { nil }
	listener  &nethernet.Listener = unsafe { nil }
	// endpoint is the address join channel: a client given this server's
	// address asks it over HTTP instead of broadcasting for it.
	endpoint          &endpoint.EndpointHandler = unsafe { nil }
	endpoint_listener &nethernet.Listener       = unsafe { nil }
	guid              i64
	running           &stdatomic.AtomicVal[bool] = stdatomic.new_atomic[bool](false)
	// active_conns bounds concurrent connection handlers so a flood of
	// half-open/pre-login peers can't exhaust threads and CPU.
	active_conns &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	created_at   time.Time
pub mut:
	log  &logger.Logger
	lang &language.Lang
	cfg  conf.Config
}

// load_resource_packs builds the shared pack registry from local pack files and
// configured CDN packs. Returns an empty registry when disabled.
fn load_resource_packs(cfg conf.Config, log &logger.Logger, lang &language.Lang) &resourcepack.PackRegistry {
	mut reg := &resourcepack.PackRegistry{}
	if !cfg.resource_packs {
		log.info(lang.tf('server.resource_packs_loaded', {
			'Count': '0'
		}))
		return reg
	}
	for name in resourcepack.discover(cfg.resource_packs_dir) {
		path := os.join_path(cfg.resource_packs_dir, name)
		if pack := resourcepack.new_local_pack(path) {
			reg.add(pack)
			log.debug('Loaded resource pack ${pack.uuid} v${pack.version} (${pack.size} bytes)')
		} else {
			log.warn('Failed to load resource pack ${name}: ${err}')
		}
	}
	for pack in resourcepack.parse_cdn_packs(cfg.cdn_packs) {
		reg.add(pack)
		log.debug('Registered CDN resource pack ${pack.uuid} v${pack.version}')
	}
	reg.set_must_accept(cfg.force_resource_packs || !cfg.allow_client_packs)
	log.info(lang.tf('server.resource_packs_loaded', {
		'Count': reg.packs.len.str()
	}))
	log.debug('Resource packs must_accept=${reg.must_accept}')
	return reg
}

// new builds a Server from opts. Every field of opts is optional - new()
// (or new(settings: my_config)) boots a fully working default server the
// same way new_hub(data) does one level down. The only propagated failure
// is a genuinely fatal one (no language could be loaded at all, not even the
// "en" fallback); everything else that can degrade gracefully (missing ops
// file, missing block palette, a world that fails to load) logs a warning
// and continues, matching the resilience the previous shape already had.
pub fn new(opts Options) !&Server {
	cfg := opts.settings
	boot_start := time.now()
	mut level := logger.Level.info
	if cfg.debug {
		level = .debug
	}
	log := logger.new(level)
	lang := language.load(cfg.language) or {
		log.warn('Failed to load language "${cfg.language}", falling back to en: ${err}')
		language.load('en') or {
			if path := crash.write_dump(cfg.crashdumps_dir, time.now().unix(),
				'fatal: language load failed', err.msg())
			{
				log.error('Wrote crash report to ${path}')
			}
			return error('failed to load any language, including the "en" fallback: ${err}')
		}
	}
	log.info(lang.tf('server.starting', {
		'Version': buildinfo.version
	}))
	log.info(lang.tf('server.loading_config', {
		'File': cfg.config_file
	}))
	log.info(lang.tf('server.language_selected', {
		'Language': cfg.language
	}))
	log.info(lang.t('server.license'))
	data := gamedata.load('data') or {
		log.warn('Failed to load game data from ./data: ${err}')
		gamedata.GameData{}
	}
	log.debug('Loaded ${data.item_entries.len} items and ${data.creative_items.len} creative entries')
	mut hub := session.new_hub(data, opts.hub_options)
	hub.set_lang(lang)
	hub.set_initial_difficulty(conf.difficulty_from_string(cfg.difficulty))
	hub.set_conf_file(cfg.config_file)
	hub.set_ops(permission.load_ops(cfg.ops_file) or {
		log.warn('Failed to load ops file: ${err}')
		permission.OpList{}
	})
	perm_cfg := permission.load_permissions_config(cfg.permissions_file) or {
		log.warn('Failed to load permissions config: ${err}')
		permission.PermissionsConfig{}
	}
	for cmd_name in perm_cfg.disabled_commands {
		hub.unregister_command(cmd_name)
		log.info('Command "${cmd_name}" disabled via ${cfg.permissions_file}')
	}
	hub.set_player_grants(permission.load_player_grants(cfg.player_permissions_file) or {
		log.warn('Failed to load player permissions file: ${err}')
		permission.PlayerGrants{}
	})
	hub.set_whitelist(permission.load_whitelist(cfg.whitelist_file) or {
		log.warn('Failed to load whitelist: ${err}')
		permission.Whitelist{}
	})
	// Only override the default provider's directory, a caller who already
	// supplied their own player_data_provider knows what they're doing.
	if opts.hub_options.player_data_provider == none {
		hub.set_player_data_provider(playerdb.FileProvider{
			dir: cfg.players_dir
		})
	}
	if palette := world.load_palette(os.join_path('data', 'block_palette.nbt')) {
		hub.set_palette(palette)
		log.debug('Loaded ${palette.len()} block states')
	} else {
		log.warn('Failed to load block palette: ${err}')
	}
	hub.set_packs(load_resource_packs(cfg, log, lang))
	// Every parse above is done and its garbage is dead, and no world thread or
	// chunk worker exists yet. The collector scans thread stacks conservatively,
	// so once those threads are running a dead block is far more likely to look
	// reachable and stay mapped - releasing here is what actually returns the
	// parse peak rather than carrying it for the process's lifetime.
	release_free_heap()
	log.debug('After data load ${heap_summary()}')
	hub.load_configured_worlds(cfg.worlds_dir, cfg.default_world, cfg.load_all_worlds,
		cfg.generator, log, lang)
	return &Server{
		log:        log
		lang:       lang
		cfg:        cfg
		hub:        hub
		guid:       rand.i64()
		created_at: boot_start
	}
}

// TransportLogSink forwards what the NetherNet stack logs into the server's own
// logger, so transport diagnostics land in the same place as everything else.
struct TransportLogSink {
	log &logger.Logger = unsafe { nil }
}

fn (s &TransportLogSink) write(level logging.Level, scope string, msg string) {
	line := '[${scope}] ${msg}'
	match level {
		.error { s.log.error(line) }
		.warn { s.log.warn(line) }
		.info { s.log.info(line) }
		else { s.log.debug(line) }
	}
}

// transport_log_level keeps the transport quiet unless the server is in debug
// mode: ICE and DTLS negotiation is verbose enough to bury the game log.
fn (s &Server) transport_log_level() logging.Level {
	return if s.cfg.debug { logging.Level.debug } else { logging.Level.warn }
}

// start binds the transport listeners (NetherNet & LAN discovery) and
// begins accepting connections and ticking loaded worlds. Blocks the
// calling thread for the life of the server; call it last. Returns an
// error if the network identity or a listener fails to bind.
pub fn (mut s Server) start() ! {
	s.log.info(s.lang.tf('server.supported_version', {
		'Version': proto.selected_minecraft_version
	}))
	net_log := logging.new('nethernet', s.transport_log_level(), &TransportLogSink{
		log: s.log
	})
	// Both listeners answer under the same stored key, so a client reaching the
	// server either way sees one identity.
	identity := network.load_identity(s.cfg.identity_file, nethernet_identity_domain)!
	// The server answers requests rather than making them, so it binds the
	// discovery port and never broadcasts. The port is fixed and shared by
	// every server on the host, so losing it only costs LAN visibility: the
	// address join channel below still accepts players.
	mut signaling := &discovery.Listener(unsafe { nil })
	mut listener := &nethernet.Listener(unsafe { nil })
	if mut sig := discovery.listen('${s.cfg.address}:${discovery.default_port}',
		network_id: u64(s.guid)
		broadcast:  false
		logger:     net_log
	)
	{
		sig.pong_data(s.pong_data(0).bytes())
		listener = nethernet.listen(mut sig,
			// The game leaves the identity assertion out of most of its offers,
			// including every LAN one, so refusing them is opt in. Xbox Live
			// authentication is checked on the Login chain instead.
			allow_anonymous: !s.cfg.require_identity
			identity:        identity
			logger:          net_log
		) or {
			sig.close()
			return err
		}
		signaling = sig
	} else {
		s.log.warn(s.lang.tf('server.discovery_unavailable', {
			'Address': '${s.cfg.address}:${discovery.default_port}'
			'Error':   err.msg()
		}))
	}
	mut join_endpoint := endpoint.listen(
		address:    s.cfg.bind_address()
		network_id: s.guid.str()
		logger:     net_log
	) or {
		if !isnil(listener) {
			listener.close()
			signaling.close()
		}
		return err
	}
	join_endpoint.pong_data(s.pong_data(0).bytes())
	mut endpoint_listener := nethernet.listen(mut join_endpoint,
		allow_anonymous: !s.cfg.require_identity
		identity:        identity
		logger:          net_log
	) or {
		join_endpoint.close()
		if !isnil(listener) {
			listener.close()
			signaling.close()
		}
		return err
	}
	s.signaling = signaling
	s.listener = listener
	s.endpoint = join_endpoint
	s.endpoint_listener = endpoint_listener
	s.running.store(true)
	s.log.info(s.lang.tf('server.listening', {
		'Address': s.cfg.bind_address()
	}))
	if !isnil(signaling) {
		s.log.info(s.lang.tf('server.discovery_listening', {
			'Address': '${s.cfg.address}:${discovery.default_port}'
		}))
	}
	// Boot is the process's allocation peak and none of its parse garbage is
	// needed again, so this is the one point where returning it is free.
	release_free_heap()
	s.log.debug('After boot ${heap_summary()}')
	elapsed := (time.now() - s.created_at).seconds()
	s.log.info(s.lang.tf('server.started', {
		'Seconds': '${elapsed:.3f}'
	}))
	spawn s.tick_loop()
	spawn s.console_loop()
	if !isnil(listener) {
		spawn s.accept_loop(mut listener)
	}
	s.accept_loop(mut endpoint_listener)
}

const console_poll_interval = 100 * time.millisecond

// console_loop reads command lines from stdin and dispatches them through the
// shared command registry as CONSOLE, mirroring the in-game chat path.
fn (mut s Server) console_loop() {
	logger.name_thread('Console Thread')
	defer {
		logger.unname_thread()
	}
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
		chunk_cache_entries, chunk_cache_bytes := s.hub.chunk_cache_totals()
		ctx := cmd.Context{
			lang:                          s.lang
			sender_name:                   sender.name()
			player_count:                  s.hub.count()
			max_players:                   s.cfg.max_players
			server_motd:                   s.cfg.motd
			uptime_seconds:                s.hub.uptime_seconds()
			tps:                           s.hub.tps()
			load:                          s.hub.load()
			memory_used_bytes:             i64(gc_memory_use())
			memory_heap_bytes:             i64(gc_heap_usage().heap_size)
			active_chunk_generation_count: s.hub.active_chunk_generation_count()
			chunk_cache_entries:           i64(chunk_cache_entries)
			chunk_cache_bytes:             chunk_cache_bytes
		}
		s.hub.dispatch_command(line, mut sender, ctx) or {
			s.log.error('Console command failed: ${err}')
		}
	}
}

fn (mut s Server) tick_loop() {
	logger.name_thread('Server Thread')
	defer {
		logger.unname_thread()
	}
	interval := time.second / ticks_per_second
	loop_start := time.now()
	mut tick := u64(0)
	mut window_start := time.now()
	mut window_ticks := 0
	mut window_work := i64(0)
	// Carried between ticks so every tick has a meaningful value, even on the
	// 19 out of 20 ticks that don't recompute the window.
	mut tps := f64(ticks_per_second)
	mut load := f64(0)
	mut last_overrun_log := u64(0)
	for s.running.load() {
		tick_start := time.now()
		tick++
		world_time := int(tick % day_length_ticks)
		if tick % u64(ticks_per_second) == 0 {
			s.hub.broadcast(&proto.SetTimePacket{
				time: world_time
			})
			pong := s.pong_data(s.hub.count()).bytes()
			if !isnil(s.signaling) {
				s.signaling.pong_data(pong)
			}
			s.endpoint.pong_data(pong)
		}
		if tick % world_flush_interval_ticks == 0 {
			for msg in s.hub.flush_worlds() {
				s.log.warn('World flush failed: ${msg}')
			}
		}
		if tick % heap_release_interval_ticks == 0 {
			release_free_heap()
		}
		if tick % persist_pressure_log_interval == 0 {
			for msg in s.hub.persist_pressure_warnings() {
				s.log.warn(msg)
			}
		}
		s.hub.request_tick_all(i64(tick))
		// Global cadence/metrics/scheduler heartbeat are direct: none of this
		// needs actor serialization, current_tick/tps/load are atomics and the
		// scheduler guards its own bookkeeping with its own mutex. Effects
		// ticking, the one piece that genuinely is gameplay mutation, happens
		// in each owning world's own advance_tick instead (world_runtime.v), not
		// here.
		s.hub.set_current_tick(i64(tick))
		s.hub.scheduler_heartbeat(i64(tick))
		// Measured once every piece of tick work has run. Taking it before the
		// dispatch and heartbeat above left them out of the sample, which is what
		// made load read 0% on a tick that had just reported itself over budget.
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
		s.hub.set_tps(tps)
		s.hub.set_load(load)
		deadline := loop_start.add(time.Duration(i64(interval) * i64(tick)))
		sleep_for := deadline - time.now()
		if sleep_for > 0 {
			time.sleep(sleep_for)
		} else {
			// The deadline passed. We don't sleep, so the loop catches up on the
			// next iterations. The deadline is anchored to loop_start, so a burst
			// of missed slots can't compound into runaway drift - once the loop
			// keeps up again, sleep_for goes positive and the cadence
			// self-corrects.
			//
			// Only the tick's own work being over budget is worth warning about.
			// time.sleep overshoots its request by a few ms on a loaded host, and
			// that alone pushes the next deadline into the past on an otherwise
			// idle server - a missed slot the operator can do nothing about.
			over := -sleep_for
			if work <= interval {
				s.log.debug('Tick ${tick} slot missed by ${over.milliseconds()}ms with ${work.milliseconds()}ms of work - sleep overshoot, not server load')
			} else if tick - last_overrun_log >= tick_overrun_log_interval {
				s.log.warn('Tick ${tick} took ${work.milliseconds()}ms, over its ${interval.milliseconds()}ms budget (tps=${tps:.1f}, load=${load:.0f}%)')
				last_overrun_log = tick
			}
		}
	}
}

// max_concurrent_connections caps how many connection handlers run at once.
const max_concurrent_connections = u64(1024)

// accept_loop takes connections from one of the two channels a client can
// arrive through. Both end in the same handler: how the connection was
// negotiated says nothing about the session that follows.
fn (mut s Server) accept_loop(mut listener nethernet.Listener) {
	logger.name_thread('Network Listener')
	defer {
		logger.unname_thread()
	}
	for s.running.load() {
		mut conn := listener.accept(time.second) or { continue }
		peer_addr := network.remote_endpoint(conn.remote_addr())
		if s.active_conns.load() >= max_concurrent_connections {
			s.log.warn('Rejecting connection from ${peer_addr} - at capacity (${max_concurrent_connections})')
			conn.close()
			continue
		}
		s.active_conns.add(1)
		s.log.info('Incoming connection from ${peer_addr}')
		spawn s.handle(mut conn)
	}
}

// handle runs one connection on its own spawned thread. It is the isolation
// boundary for a single client: every error path inside handle_loop ends in a
// disconnect for that session only, and nothing here propagates back out of the
// thread, so one misbehaving connection can never take the server down. The
// remote address is captured up front so a failure setting up the session still
// has something to log against.
fn (mut s Server) handle(mut conn nethernet.Conn) {
	defer {
		s.active_conns.sub(1)
	}
	addr := network.remote_endpoint(conn.remote_addr())
	// Renamed to the player's display name once login resolves one, so a
	// session's lines are attributable before and after it has an identity.
	logger.name_thread('Connection/${addr}')
	defer {
		logger.unname_thread()
	}
	mut transport := network.new_session(mut conn, s.log)
	mut net_session := session.new(mut transport, mut s.hub, s.cfg, s.log)
	net_session.handle_loop()
	s.log.debug('Connection handler for ${addr} finished')
}

// pong_data is the semicolon separated status string both signalling channels
// advertise the server with. The port appears twice because the format keeps
// one for each address family.
fn (s &Server) pong_data(online int) string {
	gamemode, gamemode_num := normalize_gamemode(s.cfg.gamemode)
	return
		['MCPE', s.cfg.motd, proto.selected_protocol.str(), proto.selected_minecraft_version, online.str(), s.cfg.max_players.str(), s.guid.str(), s.cfg.sub_motd, gamemode, gamemode_num.str(), s.cfg.port.str(), s.cfg.port.str()].join(';') +
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

// stop disconnects every session and waits for each one to finish leaving
// including player data saves, before shutting down worlds or the listener.
// It returns only after all players have fully disconnected.
pub fn (mut s Server) stop() {
	if !s.running.load() {
		return
	}
	s.log.info('Stopping server')
	s.running.store(false)
	if !isnil(s.hub) {
		s.hub.disconnect_all('Server closed')
		s.hub.wait_for_sessions_to_leave()
		s.hub.close_worlds()
	}
	if !isnil(s.endpoint_listener) {
		s.endpoint_listener.close()
	}
	if !isnil(s.endpoint) {
		s.endpoint.close()
	}
	if !isnil(s.listener) {
		s.listener.close()
	}
	if !isnil(s.signaling) {
		s.signaling.close()
	}
}

// register_event adds handler to the server's global event bus.
pub fn (mut s Server) register_event(handler event.Handler, priority event.Priority) {
	s.hub.register_event(handler, priority)
}

// unregister_event removes handler from the global event bus.
pub fn (mut s Server) unregister_event(handler event.Handler) {
	s.hub.unregister_event(handler)
}

// register_command adds command to the server's command registry.
pub fn (mut s Server) register_command(command cmd.Command) {
	s.hub.register_command(command)
}

// unregister_command removes a previously registered command.
pub fn (mut s Server) unregister_command(name string) {
	s.hub.unregister_command(name)
}

// run_task schedules task to run on the server's global tick thread on the
// next tick. Tasks must remain short, non blocking and world independent.
pub fn (mut s Server) run_task(task scheduler.Task) &scheduler.TaskHandler {
	return s.hub.run_task(task)
}

// run_delayed queues task to run once, delay ticks from now.
pub fn (mut s Server) run_delayed(task scheduler.Task, delay i64) &scheduler.TaskHandler {
	return s.hub.run_delayed(task, delay)
}

// run_repeating queues task to run every period ticks, starting next tick.
pub fn (mut s Server) run_repeating(task scheduler.Task, period i64) &scheduler.TaskHandler {
	return s.hub.run_repeating(task, period)
}

// See: hub.cancel_task
pub fn (mut s Server) cancel_task(id int) {
	s.hub.cancel_task(id)
}

// WorldConfig is what load_world needs to bring a world up: its name,
// dimension and which registered generator to use.
//
// dimension/generator_name only matter the first time this name is
// created on disk. Reopening an existing world just reuses whatever
// generator/dimension it was saved with.
//
// To use a custom generator, register it with Server.register_generator
// first, then reference it by name here.
@[params]
pub struct WorldConfig {
pub:
	name           string
	dimension      world.Dimension = world.overworld
	generator_name string
}

// load_world returns the loaded world, loading it from storage or creating
// it when necessary. Repeated calls for the same world return the existing
// handle.
//
// The underlying world lifecycle remains owned by Hub.
pub fn (mut s Server) load_world(config WorldConfig) !session.World {
	if handle := s.hub.world_handle(config.name) {
		return handle
	}
	s.hub.load_or_create_world(config.name, config.dimension, config.generator_name)!
	return s.hub.world_handle(config.name) or {
		error('world "${config.name}" failed to register after loading')
	}
}

// world returns the named world's public handle, or none if it's not
// currently loaded. Use load_world to load or create a world on demand.
pub fn (mut s Server) world(name string) ?session.World {
	return s.hub.world_handle(name)
}

// worlds returns a handle for every currently loaded world.
pub fn (mut s Server) worlds() []session.World {
	names := s.hub.list_worlds()
	mut out := []session.World{cap: names.len}
	for name in names {
		if handle := s.hub.world_handle(name) {
			out << handle
		}
	}
	return out
}

// unload_world stops and releases a loaded world without deleting its
// stored data. It refuses to unload the default world or a world that still
// contains players; callers must move or disconnect them first.
pub fn (mut s Server) unload_world(name string) ! {
	s.hub.unload_world(name)!
}

// register_generator makes a custom world generator available under name,
// so load_world/WorldConfig can select it by that name for a new world.
// Register before loading any world that uses it.
pub fn (mut s Server) register_generator(name string, factory fn (dim world.Dimension) world.Generator) {
	s.hub.register_generator(name, factory)
}

// player returns the currently connected player with the given name or
// none if no such player is connected. The returned PlayerRef is
// stale checked and may be safely held for later use.
pub fn (mut s Server) player(name string) ?session.PlayerRef {
	return s.hub.player_ref(name)
}

// players returns a PlayerRef for every player currently connected to the
// server across all loaded worlds. It doesn't require a world actor round trip.
pub fn (mut s Server) players() []session.PlayerRef {
	return s.hub.player_refs()
}

// player_count returns how many players are currently connected.
pub fn (mut s Server) player_count() int {
	return s.hub.count()
}
