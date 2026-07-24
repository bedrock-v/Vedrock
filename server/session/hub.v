module session

import sync
import sync.stdatomic
import math
import time
import protocol
import protocol.enums
import server.event
import server.scheduler
import server.entity
import server.internal.gamedata
import server.item
import server.block
import server.internal.language
import server.cmd
import server.cmd.default as defaultcmd
import server.world as blockworld
import server.world.db
import server.resource
import server.permission
import server.enchant
import server.internal.auth

@[heap]
pub struct Hub {
mut:
	sessions        map[u64]&NetworkSession
	pending_names   map[string]bool
	mutex           &sync.Mutex               = sync.new_mutex()
	next_runtime_id u64                       = 1
	tps_bits        &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](math.f64_bits(20.0))
	// config_mutex guards server global mutable config: ops, whitelist and
	// difficulty. Runtime reads/writes must use the locked accessors below;
	// the raw fields are assigned only during boot before network threads
	// start.
	config_mutex &sync.Mutex               = sync.new_mutex()
	load_bits    &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	online_count &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	// current_tick_bits backs current_tick()/set_current_tick(). Written
	// directly from server.v's tick loop while other threads still read it
	// (blocks.v's cooldown tracking, movement.v's tick check), so it's an
	// atomic like the other tick metrics.
	current_tick_bits &stdatomic.AtomicVal[i64] = stdatomic.new_atomic[i64](0)
	// world_registry owns loaded world runtimes and their lifecycle. Hub
	// routes named lookups through it instead of storing raw worlds directly.
	world_registry &WorldRegistry = unsafe { nil }
	// oidc_verifier checks modern Xbox Live single token logins (see
	// auth.parse_identity_token). Built once here so its discovered
	// issuer and JWKS cache are shared across every login for the life of
	// the process.
	oidc_verifier &auth.OidcVerifier = auth.new_oidc_verifier()
pub mut:
	data               gamedata.GameData
	items              item.Registry                = item.new_registry()
	blocks             block.Registry               = block.new_registry()
	lang               &language.Lang               = unsafe { nil }
	commands           cmd.Registry                 = cmd.new_registry()
	events             &event.Bus                   = unsafe { nil }
	scheduler          &scheduler.Scheduler         = unsafe { nil }
	entity_registry    entity.Registry              = entity.new_registry()
	custom_items       item.CustomRegistry          = item.new_custom_registry()
	custom_blocks      block.CustomRegistry         = block.new_custom_registry()
	custom_entities    entity.CustomRegistry        = entity.new_custom_registry()
	enchantments       enchant.Registry             = enchant.new_registry()
	generators         blockworld.GeneratorRegistry = blockworld.new_generator_registry()
	started_at         i64
	default_world_name string
	// worlds_dir is the on-disk root for world folders and world_generator the
	// fallback generator name for freshly created worlds. Both are set at boot.
	worlds_dir      string = 'worlds'
	world_generator string = 'flat'
	// world_factory creates/opens/lists/deletes named world backends.
	// Defaults to db.LevelDBFactory the first time set_world_config runs,
	// unless HubOptions already supplied one at construction time.
	world_factory ?db.Factory
	packs         &resource.PackRegistry   = unsafe { nil }
	palette       &blockworld.BlockPalette = unsafe { nil }
	ops           permission.OpList
	player_grants permission.PlayerGrants
	whitelist     permission.Whitelist
	difficulty    int = protocol.difficulty_easy
	// conf_file is the path to this instance's own settings file (set from
	// conf.Config.config_file, not a shared default) so runtime difficulty
	// changes persist back to the correct per instance file.
	conf_file string
}

// current_tick is the global tick counter, published directly from
// server.v's tick loop (set_current_tick). See current_tick_bits' own
// comment for why this is an atomic rather than a plain field.
pub fn (mut h Hub) current_tick() i64 {
	return h.current_tick_bits.load()
}

pub fn (mut h Hub) set_current_tick(v i64) {
	h.current_tick_bits.store(v)
}

pub fn (mut h Hub) tps() f64 {
	return math.f64_from_bits(h.tps_bits.load())
}

// set_tps/set_load are called directly from server.v's tick loop.
pub fn (mut h Hub) set_tps(v f64) {
	h.tps_bits.store(math.f64_bits(v))
}

pub fn (mut h Hub) load() f64 {
	return math.f64_from_bits(h.load_bits.load())
}

pub fn (mut h Hub) set_load(v f64) {
	h.load_bits.store(math.f64_bits(v))
}

// HubOptions overrides Hub's default subsystems - the framework-level
// injection point. Every field left unset falls back to Vedrock's own
// built-in default, mirroring Dragonfly's Config.New() defaulting pattern:
// new_hub(data) with no options still boots a fully working default server.
@[params]
pub struct HubOptions {
pub:
	commands        ?cmd.Registry
	entity_registry ?entity.Registry
	world_factory   ?db.Factory
}

pub fn new_hub(data gamedata.GameData, opts HubOptions) &Hub {
	mut commands := opts.commands or {
		mut c := cmd.new_registry()
		defaultcmd.register_all(mut c)
		c
	}

	mut registry := opts.entity_registry or {
		mut r := entity.new_registry()
		entity.register_defaults(mut r)
		r
	}

	mut hub := &Hub{
		sessions:        map[u64]&NetworkSession{}
		pending_names:   map[string]bool{}
		mutex:           sync.new_mutex()
		data:            data
		commands:        commands
		events:          event.new_bus()
		scheduler:       scheduler.new_scheduler()
		entity_registry: registry
		world_factory:   opts.world_factory
		started_at:      time.now().unix()
		world_registry:  new_world_registry()
	}
	hub.register_palette_fallbacks()
	return hub
}

// register_palette_fallbacks backfills the block and item registries from the
// wire palette so every vanilla name is placeable/holdable even before it has
// a hand written class. Hand registered classes always take precedence.
fn (mut h Hub) register_palette_fallbacks() {
	mut block_entries := []block.PaletteEntry{cap: h.data.block_palette.len}
	mut canonical := map[string]int{}
	for e in h.data.block_palette {
		block_entries << block.PaletteEntry{
			name:       e.name
			network_id: e.network_id
		}
		if e.name !in canonical {
			canonical[e.name] = e.network_id
		}
	}
	h.blocks.register_fallbacks(block_entries)

	mut item_entries := []item.FallbackEntry{cap: h.data.item_entries.len}
	for it in h.data.item_entries {
		item_entries << item.FallbackEntry{
			id:            it.name
			block_runtime: canonical[it.name] or { 0 }
		}
	}
	h.items.register_fallbacks(item_entries)
}

pub fn (h &Hub) uptime_seconds() i64 {
	return time.now().unix() - h.started_at
}

// add_world wraps a loaded world in a WorldRuntime (starting its actor) and
// registers it under its name. The first world added becomes the default
// unless one is already set.
pub fn (mut h Hub) add_world(loaded_world &db.World) {
	wr := new_world_runtime(h, loaded_world)
	h.world_registry.add(wr)
	h.mutex.lock()
	if h.default_world_name == '' {
		h.default_world_name = loaded_world.name
	}
	h.mutex.unlock()
}

pub fn (mut h Hub) set_default_world(name string) {
	h.mutex.lock()
	h.default_world_name = name
	h.mutex.unlock()
}

// world_runtime looks up the named world's runtime. Gameplay packets normally
// use the session's current binding; named lookup is for world commands and
// transfers.
fn (h &Hub) world_runtime(name string) ?&WorldRuntime {
	mut r := h.world_registry
	return r.get(name) or { return none }
}

// request_tick_all pulses every loaded world's own coalesced tick wakeup.
pub fn (mut h Hub) request_tick_all(n i64) {
	mut r := h.world_registry
	for mut wr in r.each_runtime() {
		wr.request_tick(n)
	}
}

pub fn (mut h Hub) world(name string) ?&db.World {
	wr := h.world_runtime(name) or { return none }
	return wr.world
}

// default_world returns the world new players spawn into, or none when no
// world could be loaded.
pub fn (mut h Hub) default_world() ?&db.World {
	h.mutex.lock()
	name := h.default_world_name
	h.mutex.unlock()
	return h.world(name)
}

// default_world_runtime is default_world's routing path counterpart.
fn (mut h Hub) default_world_runtime() ?&WorldRuntime {
	h.mutex.lock()
	name := h.default_world_name
	h.mutex.unlock()
	return h.world_runtime(name)
}

pub fn (mut h Hub) world_count() int {
	mut r := h.world_registry
	return r.len()
}

// close_worlds shuts down and releases every loaded world's runtime. Called
// once on shutdown after all sessions are disconnected. Runtimes are removed
// from the registry before shutdown, so new named lookups cannot find a world
// that is stopping.
pub fn (mut h Hub) close_worlds() {
	mut r := h.world_registry
	for mut wr in r.each_runtime() {
		r.remove(wr.world.name)
		wr.shutdown()
		wr.world.close()
	}
}

// set_world_config records where worlds live on disk and the default generator
// used for worlds created at runtime. Called once at boot from load_worlds.
pub fn (mut h Hub) set_world_config(worlds_dir string, generator string) {
	h.mutex.lock()
	h.worlds_dir = worlds_dir
	h.world_generator = generator
	if h.world_factory == none {
		h.world_factory = db.LevelDBFactory{
			worlds_dir: worlds_dir
		}
	}
	h.mutex.unlock()
}

// list_worlds returns the names of every loaded world.
pub fn (mut h Hub) list_worlds() []string {
	mut r := h.world_registry
	return r.names()
}

// WorldInfo is a read-only snapshot describing a loaded world.
pub struct WorldInfo {
pub:
	name       string
	generator  string
	dimension  string
	overrides  int
	is_default bool
	players    int
}

// world_info gathers a snapshot for the named world, or none when it isn't
// loaded.
pub fn (mut h Hub) world_info(name string) ?WorldInfo {
	loaded_world := h.world(name) or { return none }
	h.mutex.lock()
	is_default := name == h.default_world_name
	h.mutex.unlock()
	return WorldInfo{
		name:       loaded_world.name
		generator:  loaded_world.generator_name
		dimension:  loaded_world.dimension.name()
		overrides:  loaded_world.block_count()
		is_default: is_default
		players:    h.players_in_world(name)
	}
}

// players_in_world counts the connected players whose active world matches name.
pub fn (mut h Hub) players_in_world(name string) int {
	h.mutex.lock()
	defer { h.mutex.unlock() }
	mut count := 0
	for _, target in h.sessions {
		if target.world_name() == name {
			count++
		}
	}
	return count
}

// sessions_in_world returns every connected session whose active world
// matches name. Used for world scoped broadcasting.
pub fn (mut h Hub) sessions_in_world(name string) []&NetworkSession {
	h.mutex.lock()
	defer { h.mutex.unlock() }
	mut list := []&NetworkSession{}
	for _, target in h.sessions {
		if target.world_name() == name {
			list << target
		}
	}
	return list
}

// register_generator adds or overrides a named world generator. Part of the
// plugin.ServerView surface.
pub fn (mut h Hub) register_generator(name string, factory fn (dim blockworld.Dimension) blockworld.Generator) {
	h.generators.register(name, factory)
}

// generator_type_names lists every registered generator name. Part of the
// plugin.ServerView surface.
pub fn (mut h Hub) generator_type_names() []string {
	return h.generators.names()
}

// build_generator resolves a world's own generator by name and dimension
// through the registry.
pub fn (h &Hub) build_generator(w &db.World) blockworld.Generator {
	return h.generators.create(w.generator_name, w.dimension) or {
		h.generators.create(w.dimension.default_generator, w.dimension) or {
			blockworld.new_generator(w.generator_name)
		}
	}
}

// create_world creates a fresh empty world on disk and registers it as loaded.
// Refuses to clobber an already-loaded or already-on-disk world. Safe to call
// off the actor thread - it only adds to the worlds map, never mutates a
// player's active world.
pub fn (mut h Hub) create_world(name string, dim blockworld.Dimension, generator string) !string {
	if _ := h.world(name) {
		return error('world "${name}" is already loaded')
	}
	h.mutex.lock()
	mut factory := h.world_factory or {
		h.mutex.unlock()
		return error('world factory not configured')
	}

	default_generator := if dim.id == blockworld.overworld.id {
		h.world_generator
	} else {
		dim.default_generator
	}
	h.mutex.unlock()
	resolved_generator := if generator.trim_space() == '' { default_generator } else { generator }
	provider := factory.create(name, dim, resolved_generator) or {
		return error('failed to create world "${name}": ${err}')
	}
	loaded_world := db.new_world(name, provider, resolved_generator, dim)
	h.add_world(loaded_world)
	return name
}

pub fn (mut h Hub) load_world(name string) !string {
	if _ := h.world(name) {
		return error('world "${name}" is already loaded')
	}
	h.mutex.lock()
	mut factory := h.world_factory or {
		h.mutex.unlock()
		return error('world factory not configured')
	}

	default_generator := h.world_generator
	h.mutex.unlock()
	if !factory.exists(name) {
		return error('world "${name}" does not exist on disk')
	}
	loaded_world := factory.open(name, default_generator, blockworld.overworld) or {
		return error('failed to load world "${name}": ${err}')
	}
	h.add_world(loaded_world)
	return name
}

// unload_world flushes and releases a loaded world without deleting its
// files. Refuses the default world and any world that still has players in it.
pub fn (mut h Hub) unload_world(name string) ! {
	h.mutex.lock()
	if name == h.default_world_name {
		h.mutex.unlock()
		return error('cannot unload the default world')
	}
	h.mutex.unlock()
	mut r := h.world_registry
	mut wr := r.get(name) or { return error('world "${name}" is not loaded') }
	if h.players_in_world(name) > 0 {
		return error('world "${name}" still has players in it')
	}
	r.remove(name)
	wr.shutdown()
	wr.world.close()
}

// delete_world unloads the named world and removes its on-disk folder. Refuses
// the default world and any world that still has players in it. The LevelDB
// handle is always closed before the files are touched.
pub fn (mut h Hub) delete_world(name string) ! {
	h.mutex.lock()
	if name == h.default_world_name {
		h.mutex.unlock()
		return error('cannot delete the default world')
	}
	mut factory := h.world_factory or {
		h.mutex.unlock()
		return error('world factory not configured')
	}

	h.mutex.unlock()

	mut r := h.world_registry
	loaded := r.get(name) != none
	if h.players_in_world(name) > 0 {
		return error('world "${name}" still has players in it')
	}
	if loaded {
		// unload_world closes the handle so the files are no longer held open.
		h.unload_world(name)!
	} else if !factory.exists(name) {
		return error('world "${name}" does not exist')
	}
	factory.delete(name) or { return error('failed to delete world "${name}": ${err}') }
}

pub fn (mut h Hub) allocate_runtime_id() u64 {
	h.mutex.lock()
	id := h.next_runtime_id
	h.next_runtime_id++
	h.mutex.unlock()
	return id
}

pub fn (mut h Hub) add(target &NetworkSession) {
	h.mutex.lock()
	h.sessions[target.runtime_id] = target
	h.pending_names.delete(normal_player_name(target.player.identity.display_name))
	h.mutex.unlock()
	h.online_count.add(1)
}

pub fn (mut h Hub) remove(runtime_id u64) {
	h.mutex.lock()
	h.sessions.delete(runtime_id)
	h.mutex.unlock()
	h.online_count.sub(1)
}

pub fn (mut h Hub) session_by_runtime(runtime_id u64) ?&NetworkSession {
	h.mutex.lock()
	target := h.sessions[runtime_id] or {
		h.mutex.unlock()
		return none
	}
	h.mutex.unlock()
	return target
}

pub fn (mut h Hub) session_by_name(name string) ?&NetworkSession {
	h.mutex.lock()
	defer { h.mutex.unlock() }
	// I'm not sure about trim_space().to_lower(), so let's use casual to_lower
	needle := name.to_lower()
	for _, target in h.sessions {
		if target.player.identity.display_name.to_lower() == needle {
			return target
		}
	}
	return none
}

fn normal_player_name(name string) string {
	return name.to_lower()
}

fn (mut h Hub) reserve_player_name(name string) bool {
	needle := normal_player_name(name)
	h.mutex.lock()
	defer {
		h.mutex.unlock()
	}
	if h.pending_names[needle] {
		return false
	}
	for _, target in h.sessions {
		if normal_player_name(target.player.identity.display_name) == needle {
			return false
		}
	}
	h.pending_names[needle] = true
	return true
}

fn (mut h Hub) admission_count() int {
	h.mutex.lock()
	defer {
		h.mutex.unlock()
	}
	return h.sessions.len + h.pending_names.len
}

fn (mut h Hub) release_player_name(name string) {
	if name == '' {
		return
	}
	h.mutex.lock()
	h.pending_names.delete(normal_player_name(name))
	h.mutex.unlock()
}

pub fn (mut h Hub) count() int {
	return int(h.online_count.load())
}

// broadcast_message sends a raw chat line to every connected player. Part of the
// plugin.ServerView surface.
pub fn (mut h Hub) broadcast_message(text string) {
	h.broadcast(&protocol.TextPacket{
		@type:   int(enums.TextType.raw)
		message: text
	})
}

// online_count is the plugin.ServerView alias for count().
pub fn (mut h Hub) online_count() int {
	return h.count()
}

// spawn_entity spawns a registered entity type in the default world. Returns
// false if the type is unknown, the default world is unavailable, the runtime
// is stopping or the spawn event is cancelled. Entity registration and event
// dispatch run inside one task on that world's runtime.
pub fn (mut h Hub) spawn_entity(name string, x f32, y f32, z f32) bool {
	behaviour := h.entity_registry.create(name) or { return false }
	mut wr := h.default_world_runtime() or { return false }
	task := SpawnEntityTask{
		behaviour: behaviour
		x:         x
		y:         y
		z:         z
	}
	if !wr.submit(task) {
		return false
	}
	return <-task.result
}

// entity_type_names lists every summonable entity type.
pub fn (mut h Hub) entity_type_names() []string {
	return h.entity_registry.names()
}

// player_names lists the display names of every connected player. Part of the
// plugin.ServerView surface.
pub fn (mut h Hub) player_names() []string {
	h.mutex.lock()
	defer { h.mutex.unlock() }
	mut names := []string{cap: h.sessions.len}
	for _, target in h.sessions {
		names << target.player.identity.display_name
	}
	return names
}

fn (mut h Hub) snapshot() []&NetworkSession {
	h.mutex.lock()
	mut list := []&NetworkSession{cap: h.sessions.len}
	for _, target in h.sessions {
		list << target
	}
	h.mutex.unlock()
	return list
}

pub fn (mut h Hub) broadcast(p protocol.Packet) {
	for mut target in h.snapshot() {
		target.deliver(p)
	}
}

pub fn (mut h Hub) broadcast_except(runtime_id u64, p protocol.Packet) {
	for mut target in h.snapshot() {
		if target.runtime_id != runtime_id {
			target.deliver(p)
		}
	}
}

pub fn (mut h Hub) disconnect_all(message string) {
	for mut target in h.snapshot() {
		target.disconnect(message)
	}
}
