module session

import sync
import sync.stdatomic
import math
import time
import protocol
import protocol.enums
import protocol.types
import server.event
import server.scheduler
import server.entity
import server.liquid
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

@[heap]
pub struct Hub {
mut:
	sessions        map[u64]&NetworkSession
	mutex           &sync.Mutex = sync.new_mutex()
	next_runtime_id u64         = 1
	// jobs is the only door into gameplay-mutable state that spans sessions
	// (combat, targeted /gamemode, etc.). run_jobs() is the sole consumer.
	jobs         chan WorldJob             = chan WorldJob{cap: 256}
	tps_bits     &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](math.f64_bits(20.0))
	load_bits    &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
	online_count &stdatomic.AtomicVal[u64] = stdatomic.new_atomic[u64](0)
pub mut:
	world_time         int
	data               gamedata.GameData
	items              item.Registry                = item.new_registry()
	blocks             block.Registry               = block.new_registry()
	lang               &language.Lang               = unsafe { nil }
	commands           cmd.Registry                 = cmd.new_registry()
	events             &event.Bus                   = unsafe { nil }
	scheduler          &scheduler.Scheduler         = unsafe { nil }
	entities           &entity.Manager              = unsafe { nil }
	liquids            &liquid.LiquidManager        = unsafe { nil }
	entity_registry    entity.Registry              = entity.new_registry()
	custom_items       item.CustomRegistry          = item.new_custom_registry()
	custom_blocks      block.CustomRegistry         = block.new_custom_registry()
	custom_entities    entity.CustomRegistry        = entity.new_custom_registry()
	enchantments       enchant.Registry             = enchant.new_registry()
	generators         blockworld.GeneratorRegistry = blockworld.new_generator_registry()
	current_tick       i64
	started_at         i64
	worlds             map[string]&db.World
	default_world_name string
	// worlds_dir is the on-disk root for world folders and world_generator the
	// fallback generator name for freshly created worlds. Both are set at boot.
	worlds_dir      string                   = 'worlds'
	world_generator string                   = 'flat'
	packs           &resource.PackRegistry   = unsafe { nil }
	palette         &blockworld.BlockPalette = unsafe { nil }
	ops             permission.OpList
	player_grants   permission.PlayerGrants
	whitelist       permission.Whitelist
	difficulty int = protocol.difficulty_easy
}

pub fn (mut h Hub) tps() f64 {
	return math.f64_from_bits(h.tps_bits.load())
}

fn (mut h Hub) set_tps(v f64) {
	h.tps_bits.store(math.f64_bits(v))
}

pub fn (mut h Hub) load() f64 {
	return math.f64_from_bits(h.load_bits.load())
}

fn (mut h Hub) set_load(v f64) {
	h.load_bits.store(math.f64_bits(v))
}

pub fn new_hub(data gamedata.GameData) &Hub {
	mut commands := cmd.new_registry()
	defaultcmd.register_all(mut commands)
	mut registry := entity.new_registry()
	entity.register_defaults(mut registry)
	mut hub := &Hub{
		sessions:        map[u64]&NetworkSession{}
		mutex:           sync.new_mutex()
		data:            data
		commands:        commands
		events:          event.new_bus()
		scheduler:       scheduler.new_scheduler()
		entity_registry: registry
		started_at:      time.now().unix()
	}
	hub.entities = entity.new_manager(hub)
	hub.liquids = liquid.new_manager(hub)
	hub.register_palette_fallbacks()
	spawn hub.run_jobs()
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

// add_world registers a loaded world under its name. The first world added
// becomes the default unless one is already set.
pub fn (mut h Hub) add_world(loaded_world &db.World) {
	h.mutex.lock()
	h.worlds[loaded_world.name] = loaded_world
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

pub fn (mut h Hub) world(name string) ?&db.World {
	h.mutex.lock()
	defer { h.mutex.unlock() }
	return h.worlds[name] or { return none }
}

// default_world returns the world new players spawn into, or none when no
// world could be loaded.
pub fn (mut h Hub) default_world() ?&db.World {
	h.mutex.lock()
	defer { h.mutex.unlock() }
	return h.worlds[h.default_world_name] or { return none }
}

pub fn (mut h Hub) world_count() int {
	h.mutex.lock()
	defer { h.mutex.unlock() }
	return h.worlds.len
}

// close_worlds flushes and releases every loaded world's LevelDB handles. Called
// once on shutdown after all sessions are disconnected.
pub fn (mut h Hub) close_worlds() {
	h.mutex.lock()
	for _, mut w in h.worlds {
		w.close()
	}
	h.worlds.clear()
	h.mutex.unlock()
}

// set_world_config records where worlds live on disk and the default generator
// used for worlds created at runtime. Called once at boot from load_worlds.
pub fn (mut h Hub) set_world_config(worlds_dir string, generator string) {
	h.mutex.lock()
	h.worlds_dir = worlds_dir
	h.world_generator = generator
	h.mutex.unlock()
}

// list_worlds returns the names of every loaded world.
pub fn (mut h Hub) list_worlds() []string {
	h.mutex.lock()
	defer { h.mutex.unlock() }
	mut names := []string{cap: h.worlds.len}
	for name, _ in h.worlds {
		names << name
	}
	return names
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
	h.mutex.lock()
	loaded_world := h.worlds[name] or {
		h.mutex.unlock()
		return none
	}
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
	dir := h.worlds_dir
	default_generator := if dim.id == blockworld.overworld.id {
		h.world_generator
	} else {
		dim.default_generator
	}
	h.mutex.unlock()
	resolved_generator := if generator.trim_space() == '' { default_generator } else { generator }
	store := db.create_world_store(dir, name, dim, resolved_generator) or {
		return error('failed to create world "${name}": ${err}')
	}
	loaded_world := db.new_world(name, store, resolved_generator, dim)
	h.add_world(loaded_world)
	return name
}

pub fn (mut h Hub) load_world(name string) !string {
	if _ := h.world(name) {
		return error('world "${name}" is already loaded')
	}
	h.mutex.lock()
	dir := h.worlds_dir
	default_generator := h.world_generator
	h.mutex.unlock()
	if !db.world_exists(dir, name) {
		return error('world "${name}" does not exist on disk')
	}
	loaded_world := db.load_named(dir, name, default_generator, blockworld.overworld) or {
		return error('failed to load world "${name}": ${err}')
	}
	h.add_world(loaded_world)
	return name
}

// unload_world flushes and releases a loaded world without deleting its files.
// Refuses the default world and any world that still has players in it.
pub fn (mut h Hub) unload_world(name string) ! {
	h.mutex.lock()
	if name == h.default_world_name {
		h.mutex.unlock()
		return error('cannot unload the default world')
	}
	mut loaded_world := h.worlds[name] or {
		h.mutex.unlock()
		return error('world "${name}" is not loaded')
	}
	h.mutex.unlock()
	if h.players_in_world(name) > 0 {
		return error('world "${name}" still has players in it')
	}
	loaded_world.close()
	h.mutex.lock()
	h.worlds.delete(name)
	h.mutex.unlock()
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
	dir := h.worlds_dir
	loaded := name in h.worlds
	h.mutex.unlock()
	if h.players_in_world(name) > 0 {
		return error('world "${name}" still has players in it')
	}
	if loaded {
		// unload_world closes the handle so the files are no longer held open.
		h.unload_world(name)!
	} else if !db.world_exists(dir, name) {
		return error('world "${name}" does not exist')
	}
	db.delete_world_files(dir, name) or { return error('failed to delete world "${name}": ${err}') }
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
		if target.identity.display_name.to_lower() == needle {
			return target
		}
	}
	return none
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

// spawn_entity spawns a registered entity type by name at the given position.
// Returns false if the type is unknown. Part of the plugin.ServerView surface.
pub fn (mut h Hub) spawn_entity(name string, x f32, y f32, z f32) bool {
	behaviour := h.entity_registry.create(name) or { return false }
	h.entities.spawn(behaviour, types.Vector3{x, y, z})
	return true
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
		names << target.identity.display_name
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

// submit queues a WorldJob for run_jobs() to execute. Blocks if the queue is full.
pub fn (mut h Hub) submit(job WorldJob) {
	h.jobs <- job
}

// try_submit queues a job without blocking, returning false if the actor queue
// is full. Used for high-frequency, client- or plugin-driven jobs (attacks,
// respawns, block edits) so a flood of them can never back up connection
// threads or stall the tick loop - the excess job is simply dropped.
pub fn (mut h Hub) try_submit(job WorldJob) bool {
	select {
		h.jobs <- job {
			return true
		}
		else {
			return false
		}
	}
	return false
}

// run_jobs is the single owner thread for gameplay-mutable state that spans
// sessions. Nothing else may run a WorldJob's run().
fn (mut h Hub) run_jobs() {
	for {
		job := <-h.jobs or { break }
		job.run(mut h)
	}
}
