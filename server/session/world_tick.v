module session

// PlayerTicker advances the players in a world once per simulated step.
//
// A world runtime owns the tick clock, the catchup bound and the tick
// metrics but a player is a session concept and the runtime can't reach one.
// It calls out here instead, once per step, with the transaction for that step.
//
// This interface moves to the worldrt module with the runtime; session keeps
// the implementation.
interface PlayerTicker {
mut:
	tick_players(mut tx WorldTx)
}

// SessionPlayerTicker is the implementation for players backed by a network
// session. It holds no state: everything it needs is reachable from the
// transaction it is given.
struct SessionPlayerTicker {}

// tick_players advances effects, environmental damage and block breaking for
// every player registered in this world.
//
// It also samples each session's outbound queue depth, since this loop already
// visits every registered player once per simulated step and a separate pass
// would repeat that work purely for metrics.
fn (mut t SessionPlayerTicker) tick_players(mut tx WorldTx) {
	for mut a in tx.wr.entities.player_actors() {
		mut s := as_network_session(mut a) or { continue }
		s.tick_effects(mut tx.wr)
		s.tick_environmental_damage(mut tx)
		s.tick_breaking(mut tx)
		tx.wr.sample_outbound_depth(int(s.conn.outbound.len))
	}
}
