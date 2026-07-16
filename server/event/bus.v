module event

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
@[heap]
pub struct Bus {
mut:
	handlers []Registered
}

pub fn new_bus() &Bus {
	return &Bus{}
}

// register adds a handler at the given priority. Handlers are kept sorted so
// dispatch always walks lowest -> monitor.
pub fn (mut b Bus) register(handler Handler, priority Priority) {
	b.handlers << Registered{
		priority: priority
		order:    int(priority)
		handler:  handler
	}
	b.handlers.sort(a.order < b.order)
}

// len reports how many handlers are registered.
pub fn (b &Bus) len() int {
	return b.handlers.len
}

pub fn (mut b Bus) player_join(mut ctx Context[JoinData]) {
	for mut r in b.handlers {
		r.handler.on_player_join(mut ctx)
	}
}

pub fn (mut b Bus) player_quit(mut ctx Context[QuitData]) {
	for mut r in b.handlers {
		r.handler.on_player_quit(mut ctx)
	}
}

pub fn (mut b Bus) player_chat(mut ctx Context[ChatData]) {
	for mut r in b.handlers {
		r.handler.on_player_chat(mut ctx)
	}
}

pub fn (mut b Bus) player_command(mut ctx Context[CommandData]) {
	for mut r in b.handlers {
		r.handler.on_player_command(mut ctx)
	}
}

pub fn (mut b Bus) start_break(mut ctx Context[StartBreakData]) {
	for mut r in b.handlers {
		r.handler.on_start_break(mut ctx)
	}
}

pub fn (mut b Bus) block_break(mut ctx Context[BlockBreakData]) {
	for mut r in b.handlers {
		r.handler.on_block_break(mut ctx)
	}
}

pub fn (mut b Bus) block_place(mut ctx Context[BlockPlaceData]) {
	for mut r in b.handlers {
		r.handler.on_block_place(mut ctx)
	}
}

pub fn (mut b Bus) player_interact(mut ctx Context[InteractData]) {
	for mut r in b.handlers {
		r.handler.on_player_interact(mut ctx)
	}
}

pub fn (mut b Bus) item_use(mut ctx Context[ItemUseData]) {
	for mut r in b.handlers {
		r.handler.on_item_use(mut ctx)
	}
}

pub fn (mut b Bus) player_attack(mut ctx Context[AttackData]) {
	for mut r in b.handlers {
		r.handler.on_player_attack(mut ctx)
	}
}

pub fn (mut b Bus) player_hurt(mut ctx Context[HurtData]) {
	for mut r in b.handlers {
		r.handler.on_player_hurt(mut ctx)
	}
}

pub fn (mut b Bus) player_death(mut ctx Context[DeathData]) {
	for mut r in b.handlers {
		r.handler.on_player_death(mut ctx)
	}
}

pub fn (mut b Bus) player_respawn(mut ctx Context[RespawnData]) {
	for mut r in b.handlers {
		r.handler.on_player_respawn(mut ctx)
	}
}

pub fn (mut b Bus) player_move(mut ctx Context[MoveData]) {
	for mut r in b.handlers {
		r.handler.on_player_move(mut ctx)
	}
}

pub fn (mut b Bus) gamemode_change(mut ctx Context[GameModeChangeData]) {
	for mut r in b.handlers {
		r.handler.on_gamemode_change(mut ctx)
	}
}
