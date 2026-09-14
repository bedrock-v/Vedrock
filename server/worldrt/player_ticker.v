module worldrt

// PlayerTicker advances the players in a world once per simulated step.
//
// A world runtime owns the tick clock, the catchup bound and the tick
// metrics but a player is a session concept and the runtime can't reach one.
// It calls out here instead, once per step, with the transaction for that step.
pub interface PlayerTicker {
mut:
	tick_players(mut tx WorldTx)
}

// BlockEntityTicker advances the blocks in a world that keep running state of
// their own - a furnace part way through cooking, and whatever else comes to
// need it.
//
// It exists for the same reason PlayerTicker does: the world runtime owns the
// clock, but what a furnace does with a tick is gameplay the runtime cannot
// reach.
pub interface BlockEntityTicker {
mut:
	tick_block_entities(mut tx WorldTx)
}
