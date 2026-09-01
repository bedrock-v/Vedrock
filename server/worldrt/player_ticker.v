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
