module event

// Handler is the listener interface: one method per event, each
// receiving a mutable Context. A plugin embeds NopHandler and overrides only the
// events it cares about.
pub interface Handler {
mut:
	on_player_join(mut ctx Context[JoinData])
	on_player_quit(mut ctx Context[QuitData])
	on_player_chat(mut ctx Context[ChatData])
	on_player_command(mut ctx Context[CommandData])
	on_start_break(mut ctx Context[StartBreakData])
	on_block_break(mut ctx Context[BlockBreakData])
	on_block_place(mut ctx Context[BlockPlaceData])
	on_player_interact(mut ctx Context[InteractData])
	on_item_use(mut ctx Context[ItemUseData])
	on_player_attack(mut ctx Context[AttackData])
	on_player_hurt(mut ctx Context[HurtData])
	on_player_death(mut ctx Context[DeathData])
	on_player_respawn(mut ctx Context[RespawnData])
	on_player_move(mut ctx Context[MoveData])
	on_gamemode_change(mut ctx Context[GameModeChangeData])
}

// NopHandler is an embeddable no-op implementation of Handler. Embed it so a
// listener satisfies the whole interface while only defining the handlers it
// actually needs.
pub struct NopHandler {}

pub fn (mut h NopHandler) on_player_join(mut ctx Context[JoinData]) {}

pub fn (mut h NopHandler) on_player_quit(mut ctx Context[QuitData]) {}

pub fn (mut h NopHandler) on_player_chat(mut ctx Context[ChatData]) {}

pub fn (mut h NopHandler) on_player_command(mut ctx Context[CommandData]) {}

pub fn (mut h NopHandler) on_start_break(mut ctx Context[StartBreakData]) {}

pub fn (mut h NopHandler) on_block_break(mut ctx Context[BlockBreakData]) {}

pub fn (mut h NopHandler) on_block_place(mut ctx Context[BlockPlaceData]) {}

pub fn (mut h NopHandler) on_player_interact(mut ctx Context[InteractData]) {}

pub fn (mut h NopHandler) on_item_use(mut ctx Context[ItemUseData]) {}

pub fn (mut h NopHandler) on_player_attack(mut ctx Context[AttackData]) {}

pub fn (mut h NopHandler) on_player_hurt(mut ctx Context[HurtData]) {}

pub fn (mut h NopHandler) on_player_death(mut ctx Context[DeathData]) {}

pub fn (mut h NopHandler) on_player_respawn(mut ctx Context[RespawnData]) {}

pub fn (mut h NopHandler) on_player_move(mut ctx Context[MoveData]) {}

pub fn (mut h NopHandler) on_gamemode_change(mut ctx Context[GameModeChangeData]) {}
