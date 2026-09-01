module worldrt

import server.event

// Handler receives what happens in a world without a player causing it. One
// world runtime has exactly one, set with handle(); a runtime without an
// explicit one carries a NopHandler.
//
// Anything a player causes belongs on player.Handler instead, including the
// admin commands that load and unload worlds.
pub interface Handler {
mut:
	on_entity_spawn(mut ctx event.Context[event.EntitySpawnData])
	on_entity_despawn(mut ctx event.Context[event.EntityDespawnData])
}

// NopHandler is an embeddable no-op implementation of Handler.
pub struct NopHandler {}

pub fn (mut h NopHandler) on_entity_spawn(mut ctx event.Context[event.EntitySpawnData]) {}

pub fn (mut h NopHandler) on_entity_despawn(mut ctx event.Context[event.EntityDespawnData]) {}
