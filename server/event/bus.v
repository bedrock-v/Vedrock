module event

import sync

// registered pairs a handler with the priority it was registered at.
struct Registered {
	priority Priority
	order    int // int(priority), kept so the list can be sorted (enums have no `<`)
mut:
	handler Handler
}

// Bus fans a dispatched Context out to every registered handler in priority
// order. It is the single event pipe the session code talks to; plugins never
// touch it directly, they register through the plugin Api.
//
// register()/unregister() are copy on write: they build an entirely new
// handlers slice (never append/remove in place) and swap it in under mutex.
// Every dispatch method takes the same mutex only to copy the current slice
// reference, then iterates that snapshot with no further locking. This makes
// concurrent register and dispatch safe without requiring dispatch to be
// confined to one thread which, for this bus specifically, it isn't:
// player_join/quit/chat/command and friends are fired directly from
// whatever session/connection thread is handling that packet, not funneled through a
// single actor.
@[heap]
pub struct Bus {
mut:
	mutex    &sync.Mutex = sync.new_mutex()
	handlers []Registered
}

pub fn new_bus() &Bus {
	return &Bus{}
}

// register adds a handler at the given priority. Builds a new slice and swaps it in , never mutates the published slice
// in place, so a dispatch already iterating the previous slice is unaffected.
pub fn (mut b Bus) register(handler Handler, priority Priority) {
	b.mutex.lock()
	mut next := b.handlers.clone()
	next << Registered{
		priority: priority
		order:    int(priority)
		handler:  handler
	}
	next.sort(a.order < b.order)
	b.handlers = next
	b.mutex.unlock()
}

// unregister removes every registration matching handler. Same
// copy on write shape as register(): builds a new slice without the
// matching entries and swaps it in, never mutating the published slice in
// place.
pub fn (mut b Bus) unregister(handler Handler) {
	b.mutex.lock()
	mut next := []Registered{cap: b.handlers.len}
	for r in b.handlers {
		if r.handler != handler {
			next << r
		}
	}
	b.handlers = next
	b.mutex.unlock()
}

// snapshot returns the currently published handler list. Dispatch methods
// call this once, then iterate the result with no further locking.
fn (mut b Bus) snapshot() []Registered {
	b.mutex.lock()
	defer {
		b.mutex.unlock()
	}
	return b.handlers
}

// len reports how many handlers are registered.
pub fn (mut b Bus) len() int {
	b.mutex.lock()
	defer {
		b.mutex.unlock()
	}
	return b.handlers.len
}

pub fn (mut b Bus) player_join(mut ctx Context[JoinData]) {
	for mut r in b.snapshot() {
		r.handler.on_player_join(mut ctx)
	}
}

pub fn (mut b Bus) player_quit(mut ctx Context[QuitData]) {
	for mut r in b.snapshot() {
		r.handler.on_player_quit(mut ctx)
	}
}

pub fn (mut b Bus) player_chat(mut ctx Context[ChatData]) {
	for mut r in b.snapshot() {
		r.handler.on_player_chat(mut ctx)
	}
}

pub fn (mut b Bus) player_command(mut ctx Context[CommandData]) {
	for mut r in b.snapshot() {
		r.handler.on_player_command(mut ctx)
	}
}

pub fn (mut b Bus) start_break(mut ctx Context[StartBreakData]) {
	for mut r in b.snapshot() {
		r.handler.on_start_break(mut ctx)
	}
}

pub fn (mut b Bus) block_break(mut ctx Context[BlockBreakData]) {
	for mut r in b.snapshot() {
		r.handler.on_block_break(mut ctx)
	}
}

pub fn (mut b Bus) block_place(mut ctx Context[BlockPlaceData]) {
	for mut r in b.snapshot() {
		r.handler.on_block_place(mut ctx)
	}
}

pub fn (mut b Bus) player_interact(mut ctx Context[InteractData]) {
	for mut r in b.snapshot() {
		r.handler.on_player_interact(mut ctx)
	}
}

pub fn (mut b Bus) item_use(mut ctx Context[ItemUseData]) {
	for mut r in b.snapshot() {
		r.handler.on_item_use(mut ctx)
	}
}

pub fn (mut b Bus) item_consume(mut ctx Context[ItemConsumeData]) {
	for mut r in b.snapshot() {
		r.handler.on_item_consume(mut ctx)
	}
}

pub fn (mut b Bus) player_attack(mut ctx Context[AttackData]) {
	for mut r in b.snapshot() {
		r.handler.on_player_attack(mut ctx)
	}
}

pub fn (mut b Bus) player_hurt(mut ctx Context[HurtData]) {
	for mut r in b.snapshot() {
		r.handler.on_player_hurt(mut ctx)
	}
}

pub fn (mut b Bus) player_death(mut ctx Context[DeathData]) {
	for mut r in b.snapshot() {
		r.handler.on_player_death(mut ctx)
	}
}

pub fn (mut b Bus) player_respawn(mut ctx Context[RespawnData]) {
	for mut r in b.snapshot() {
		r.handler.on_player_respawn(mut ctx)
	}
}

pub fn (mut b Bus) player_move(mut ctx Context[MoveData]) {
	for mut r in b.snapshot() {
		r.handler.on_player_move(mut ctx)
	}
}

pub fn (mut b Bus) gamemode_change(mut ctx Context[GameModeChangeData]) {
	for mut r in b.snapshot() {
		r.handler.on_gamemode_change(mut ctx)
	}
}

pub fn (mut b Bus) entity_spawn(mut ctx Context[EntitySpawnData]) {
	for mut r in b.snapshot() {
		r.handler.on_entity_spawn(mut ctx)
	}
}

pub fn (mut b Bus) entity_despawn(mut ctx Context[EntityDespawnData]) {
	for mut r in b.snapshot() {
		r.handler.on_entity_despawn(mut ctx)
	}
}

pub fn (mut b Bus) world_load(mut ctx Context[WorldLoadData]) {
	for mut r in b.snapshot() {
		r.handler.on_world_load(mut ctx)
	}
}

pub fn (mut b Bus) world_unload(mut ctx Context[WorldUnloadData]) {
	for mut r in b.snapshot() {
		r.handler.on_world_unload(mut ctx)
	}
}

pub fn (mut b Bus) effect_add(mut ctx Context[EffectAddData]) {
	for mut r in b.snapshot() {
		r.handler.on_effect_add(mut ctx)
	}
}

pub fn (mut b Bus) effect_remove(mut ctx Context[EffectRemoveData]) {
	for mut r in b.snapshot() {
		r.handler.on_effect_remove(mut ctx)
	}
}
