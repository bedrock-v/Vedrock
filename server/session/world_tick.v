module session

import server.worldrt

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
fn (mut t SessionPlayerTicker) tick_players(mut tx worldrt.WorldTx) {
	for mut a in tx.wr.entities.player_actors() {
		mut s := as_network_session(mut a) or { continue }
		s.player.tick_effects(mut tx)
		s.tick_environmental_damage(mut tx)
		s.tick_hunger(mut tx)
		s.tick_breaking(mut tx)
		tx.wr.sample_outbound_depth(int(s.conn.outbound.len))
	}
}
