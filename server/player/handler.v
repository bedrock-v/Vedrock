module player

import server.event

// Handler receives everything a player causes or experiences. One player has
// exactly one, set with handle(); a player without an explicit one carries a
// NopHandler, so a dispatch site never has to test whether anyone is
// listening.
//
// The split against the world's own handler follows state ownership: an event
// belongs here when the player is its subject or its cause and there when the
// world is. World load and unload are here rather than there because they are
// dispatched for the player who ran the command that loaded or unloaded.
pub interface Handler {
mut:
	on_player_join(mut ctx event.Context[JoinData])
	on_player_quit(mut ctx event.Context[QuitData])
	on_player_chat(mut ctx event.Context[ChatData])
	on_player_command(mut ctx event.Context[CommandData])
	on_start_break(mut ctx event.Context[StartBreakData])
	on_block_break(mut ctx event.Context[BlockBreakData])
	on_block_place(mut ctx event.Context[BlockPlaceData])
	on_player_interact(mut ctx event.Context[InteractData])
	on_item_use(mut ctx event.Context[ItemUseData])
	on_item_consume(mut ctx event.Context[ItemConsumeData])
	on_player_attack(mut ctx event.Context[AttackData])
	on_player_hurt(mut ctx event.Context[HurtData])
	on_player_death(mut ctx event.Context[DeathData])
	on_player_respawn(mut ctx event.Context[RespawnData])
	on_player_move(mut ctx event.Context[MoveData])
	on_gamemode_change(mut ctx event.Context[GameModeChangeData])
	on_effect_add(mut ctx event.Context[EffectAddData])
	on_effect_remove(mut ctx event.Context[EffectRemoveData])
	on_world_load(mut ctx event.Context[WorldLoadData])
	on_world_unload(mut ctx event.Context[WorldUnloadData])
}

// NopHandler is an embeddable noop implementation of Handler. Embed it so a
// handler satisfies the whole interface while only defining the events it
// actually cares about.
pub struct NopHandler {}

pub fn (mut h NopHandler) on_player_join(mut ctx event.Context[JoinData]) {}
pub fn (mut h NopHandler) on_player_quit(mut ctx event.Context[QuitData]) {}
pub fn (mut h NopHandler) on_player_chat(mut ctx event.Context[ChatData]) {}
pub fn (mut h NopHandler) on_player_command(mut ctx event.Context[CommandData]) {}
pub fn (mut h NopHandler) on_start_break(mut ctx event.Context[StartBreakData]) {}
pub fn (mut h NopHandler) on_block_break(mut ctx event.Context[BlockBreakData]) {}
pub fn (mut h NopHandler) on_block_place(mut ctx event.Context[BlockPlaceData]) {}
pub fn (mut h NopHandler) on_player_interact(mut ctx event.Context[InteractData]) {}
pub fn (mut h NopHandler) on_item_use(mut ctx event.Context[ItemUseData]) {}
pub fn (mut h NopHandler) on_item_consume(mut ctx event.Context[ItemConsumeData]) {}
pub fn (mut h NopHandler) on_player_attack(mut ctx event.Context[AttackData]) {}
pub fn (mut h NopHandler) on_player_hurt(mut ctx event.Context[HurtData]) {}
pub fn (mut h NopHandler) on_player_death(mut ctx event.Context[DeathData]) {}
pub fn (mut h NopHandler) on_player_respawn(mut ctx event.Context[RespawnData]) {}
pub fn (mut h NopHandler) on_player_move(mut ctx event.Context[MoveData]) {}
pub fn (mut h NopHandler) on_gamemode_change(mut ctx event.Context[GameModeChangeData]) {}
pub fn (mut h NopHandler) on_effect_add(mut ctx event.Context[EffectAddData]) {}
pub fn (mut h NopHandler) on_effect_remove(mut ctx event.Context[EffectRemoveData]) {}
pub fn (mut h NopHandler) on_world_load(mut ctx event.Context[WorldLoadData]) {}
pub fn (mut h NopHandler) on_world_unload(mut ctx event.Context[WorldUnloadData]) {}

// handle replaces this player's event handler. Defining none of the events is
// fine: embed NopHandler and define only what the caller cares about.
pub fn (mut p Player) handle(h Handler) {
	p.handler = h
}
